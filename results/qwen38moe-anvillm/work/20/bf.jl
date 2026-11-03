"""
Fast Brainfuck interpreter in idiomatic Julia.

Compiles code to a compact IR (integer codes) with folded runs,
precomputed bracket jumps, and `[-]` → clear-cell optimization.
Executes on a 30000-cell `UInt8` tape with wraparound arithmetic.
"""

# ── IR instruction codes ────────────────────────────────────────────────────────
const NOP       = 0
const INCR      = 1
const DECR      = 2
const ADVANCE   = 3
const RETREAT   = 4
const OUTPUT    = 5
const INPUT     = 6
const JZ_FWD    = 7   # `]`: if cell != 0 jump back to loop start; else exit
const JZ_BWD    = 8   # `[`: if cell == 0 jump to after `]`; else continue
const CLEAR     = 9   # clear-cell: `[-]`

# ── Compiler ────────────────────────────────────────────────────────────────────

"""
    compile(code::AbstractString)::Vector{Int}

Compile Brainfuck source into a compact integer-encoded IR.

Optimisations:
- Fold consecutive `+`/`-`/`<`/`>` into single instructions
- Precompute matching bracket jumps
- Replace `[-]` with a single CLEAR instruction
"""
function compile(code::AbstractString)::Vector{Int}
    n = length(code)
    if n == 0
        return Int[]
    end

    # First pass: find matching brackets (source positions)
    jump_src = Dict{Int, Int}()
    stack = Int[]
    for i in 1:n
        c = code[i]
        if c == '['
            push!(stack, i)
        elseif c == ']'
            if isempty(stack)
                error("Brainfuck: unmatched `]` at position $(i)")
            end
            j = pop!(stack)
            jump_src[i] = j
            jump_src[j] = i
        end
    end
    if !isempty(stack)
        error("Brainfuck: unmatched `[` at position $(stack[end])")
    end

    # Second pass: simulate full emit (including folding & [-] opt) to
    # record the IR position of every source character.
    ir_pos = Vector{Int}(undef, n)
    ip = 1
    i = 1
    while i <= n
        c = code[i]
        if c in ('+', '-', '<', '>')
            count = 1
            while i + count <= n && code[i + count] == c
                count += 1
            end
            for k in 1:count
                ir_pos[i + k - 1] = ip
            end
            ip += 2
            i += count
            # [-] optimization
            if c == '-' && i <= n && code[i] == ']'
                if i - count - 1 >= 1 && code[i - count - 1] == '['
                    for k in 1:1
                        ir_pos[i + k - 1] = ip
                    end
                    ip += 2
                    i += 1
                end
            end
        elseif c == '[' || c == ']'
            ir_pos[i] = ip
            ip += 2
            i += 1
        else
            ir_pos[i] = ip
            ip += 1
            i += 1
        end
    end

    # Third pass: emit IR
    buf = Int[]
    ip = 1
    i = 1
    while i <= n
        c = code[i]
        if c == '+'
            tag = INCR
        elseif c == '-'
            tag = DECR
        elseif c == '<'
            tag = ADVANCE
        elseif c == '>'
            tag = RETREAT
        elseif c == '['
            push!(buf, JZ_BWD)
            push!(buf, ir_pos[jump_src[i]] + 2)
            ip += 2
            i += 1; continue
        elseif c == ']'
            push!(buf, JZ_FWD)
            push!(buf, ir_pos[jump_src[i]] + 2)
            ip += 2
            i += 1; continue
        elseif c == '.'
            push!(buf, OUTPUT)
            ip += 1; i += 1; continue
        elseif c == ','
            push!(buf, INPUT)
            ip += 1; i += 1; continue
        else
            push!(buf, NOP)
            ip += 1; i += 1; continue
        end

        count = 1
        while i + count <= n && code[i + count] == c
            count += 1
        end
        push!(buf, tag)
        push!(buf, count)
        ip += 2
        i += count

        if tag == DECR && i <= n && code[i] == ']'
            if i - count - 1 >= 1 && code[i - count - 1] == '['
                push!(buf, CLEAR)
                push!(buf, 0)
                ip += 2
                i += 1
            end
        end
    end
    return buf
end


# ── Interpreter ─────────────────────────────────────────────────────────────────

"""
    run_bf(code::AbstractString, input::AbstractString="")::String

Execute compiled Brainfuck code and return output as a `String`.

- Tape: 30000 cells, `UInt8` with wraparound (`0x00 ± n` mod `0x100`)
- Errors: `BoundsError` for unmatched brackets (caught in compile)
            `BoundsError` for pointer leaving tape
"""
function run_bf(code::AbstractString, input::AbstractString="")::String
    ir = compile(code)
    tape = zeros(UInt8, 30000)
    ptr = 1
    ip = 1
    n_ir = length(ir)
    out_buf = IOBuffer()
    inp = input
    inp_pos = 1

    while ip <= n_ir
        tag = ir[ip]
        if tag == NOP
            ip += 1
        elseif tag == INCR
            tape[ptr] = UInt8(mod(Int(tape[ptr]) + ir[ip + 1], 256))
            ip += 2
        elseif tag == DECR
            tape[ptr] = UInt8(mod(Int(tape[ptr]) - ir[ip + 1], 256))
            ip += 2
        elseif tag == ADVANCE
            ptr -= ir[ip + 1]
            ip += 2
            if ptr < 1 || ptr > 30000
                error("Brainfuck: pointer left tape ($ptr)")
            end
        elseif tag == RETREAT
            ptr += ir[ip + 1]
            ip += 2
            if ptr < 1 || ptr > 30000
                error("Brainfuck: pointer left tape ($ptr)")
            end
        elseif tag == OUTPUT
            write(out_buf, Char(tape[ptr]))
            ip += 1
        elseif tag == INPUT
            if inp_pos <= length(inp)
                tape[ptr] = UInt8(inp[inp_pos])
                inp_pos += 1
            else
                tape[ptr] = 0
            end
            ip += 1
        elseif tag == JZ_FWD
            if tape[ptr] != 0
                ip = ir[ip + 1]
            else
                ip += 2
            end
        elseif tag == JZ_BWD
            if tape[ptr] == 0
                ip = ir[ip + 1]
            else
                ip += 2
            end
        elseif tag == CLEAR
            tape[ptr] = 0x00
            ip += 2
        else
            error("Brainfuck: unknown IR tag $tag")
        end
    end
    return String(take!(out_buf))
end


# ── Tests ───────────────────────────────────────────────────────────────────────

# "Hello World!" — classic
hello = "++++++++[>++++[>++>+++>+++>+<<<<-]>+>+>->>+[<]<-]>>.>---.+++++++..+++.>>.<-.<.+++.------.--------.>>+.>++."

# Echo: reads one byte and outputs it
echo_full = ",."

# Output 'A' (65) once: 9*7+2 = 65
prog_a = "+++++++++[>+++++++<-]>++."

# Clear tape test: `[-]` on a cell set to 1
clear_test = "+[-]"

# Unmatched bracket error
unmatched = "[++"

# Pointer out-of-bounds error
ptr_err = ">>>"

function run_tests()
    println("=== Brainfuck Tests ===\n")

    # Test 1: Hello World
    result = run_bf(hello)
    @assert result == "Hello World!\n" "Hello World failed: got $(repr(result))"
    println("✓ Hello World!")

    # Test 2: Echo (read a byte, output it)
    result = run_bf(echo_full, "X")
    @assert result == "X" "Echo failed: got $(repr(result))"
    println("✓ Echo")

    # Test 3: Read input character (read + output)
    result = run_bf(",.", "42")
    @assert result == "4" "Read input failed: got $(repr(result))"
    println("✓ Read input")

    # Test 4: Output 'A' (65)
    result = run_bf(prog_a)
    @assert result == "A" "Output A failed: got $(repr(result))"
    println("✓ Output 'A'")

    # Test 5: Clear cell
    result = run_bf(clear_test)
    @assert result == "" "Clear cell failed: got $(repr(result))"
    println("✓ Clear cell `[-]`")

    # Test 6: Unmatched bracket → error
    try
        run_bf(unmatched)
        error("Should have errored on unmatched bracket")
    catch e
        @assert occursin("unmatched", lowercase(string(e))) "Wrong error message: $e"
    end
    println("✓ Unmatched bracket error")

    # Test 7: Pointer out of bounds → error
    try
        run_bf(ptr_err)
        error("Should have errored on pointer overflow")
    catch e
        @assert occursin("pointer", lowercase(string(e))) "Wrong error message: $e"
    end
    println("✓ Pointer out-of-bounds error")

    # Test 8: Wraparound arithmetic
    wrap = "[-]-."
    result = run_bf(wrap)
    @assert result == "ÿ" "Wraparound failed: got $(repr(result))"
    println("✓ Wraparound (decrement 0 → 255)")

    # Test 9: Folded runs
    folded = "+" ^ 255
    result = run_bf(folded)
    @assert result == "" "Folded 255 '+' failed: got $(repr(result))"
    println("✓ Folded runs (255 × '+')")

    # Test 10: F-Prime (Fibonacci)
    fprime = "++++++++[>++++[>++>+++>+++>+<<<<-]>+>+>->>+[<]<-]>>.>---.+++++++..+++.>>.<-.<.+++.------.--------.>>+.>++."
    result = run_bf(fprime)
    @assert result == "Hello World!\n" "F-Prime failed: got $(repr(result))"
    println("✓ F-Prime = Hello World!")

    println("\n=== All tests passed ===")
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_tests()
end
