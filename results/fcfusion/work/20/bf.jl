# Fast Brainfuck interpreter in Julia
# Compiles to instruction vector with optimizations:
#   - folds runs of + - < > into single ops with count
#   - precomputes bracket jump targets
#   - turns [-] into a CLEAR instruction

export run_bf

const TAPE_SIZE = 30000

# Instruction opcodes
const OP_NULL = 0
const OP_ADD = 1      # add n
const OP_SUB = 2      # sub n
const OP_LEFT = 3     # move left n
const OP_RIGHT = 4    # move right n
const OP_OUT = 5
const OP_IN = 6
const OP_LOOP_START = 7
const OP_LOOP_END = 8
const OP_CLEAR = 9    # optimized [-]

mutable struct Instruction
    op::UInt8
    arg::Int
    jump::Int
end

function compile(code::AbstractString)
    n = length(code)
    # First pass: build instruction stream, fold runs
    instrs = Instruction[]
    i = 1
    while i <= n
        c = code[i]
        if c == ' ' || c == '\n' || c == '\r' || c == '\t'
            i += 1
        elseif c == '+'
            count = 0
            while i <= n && code[i] == '+'
                count += 1
                i += 1
            end
            push!(instrs, Instruction(OP_ADD, count, 0))
        elseif c == '-'
            count = 0
            while i <= n && code[i] == '-'
                count += 1
                i += 1
            end
            push!(instrs, Instruction(OP_SUB, count, 0))
        elseif c == '<'
            count = 0
            while i <= n && code[i] == '<'
                count += 1
                i += 1
            end
            push!(instrs, Instruction(OP_LEFT, count, 0))
        elseif c == '>'
            count = 0
            while i <= n && code[i] == '>'
                count += 1
                i += 1
            end
            push!(instrs, Instruction(OP_RIGHT, count, 0))
        elseif c == '.'
            push!(instrs, Instruction(OP_OUT, 0, 0))
            i += 1
        elseif c == ','
            push!(instrs, Instruction(OP_IN, 0, 0))
            i += 1
        elseif c == '['
            push!(instrs, Instruction(OP_LOOP_START, 0, 0))
            i += 1
        elseif c == ']'
            push!(instrs, Instruction(OP_LOOP_END, 0, 0))
            i += 1
        else
            throw(ErrorException("invalid character '$c' at position $i"))
        end
    end

    # Second pass: compute jump targets
    loop_starts = Int[]
    for k in 1:length(instrs)
        if instrs[k].op == OP_LOOP_START
            push!(loop_starts, k)
        elseif instrs[k].op == OP_LOOP_END
            if isempty(loop_starts)
                throw(ErrorException("unmatched ] in instruction stream"))
            end
            start_idx = pop!(loop_starts)
            instrs[start_idx].jump = k
            instrs[k].jump = start_idx
        end
    end
    if !isempty(loop_starts)
        throw(ErrorException("unmatched [ in instruction stream"))
    end

    # Third pass: optimize [-] into CLEAR
    # Pattern: SUB(n) followed by LOOP_START that jumps to LOOP_END immediately
    optimized = Instruction[]
    i = 1
    while i <= length(instrs)
        if instrs[i].op == OP_SUB &&
           i + 1 <= length(instrs) &&
           instrs[i + 1].op == OP_LOOP_START &&
           instrs[i + 1].jump == i + 2
            # This is a [-] pattern
            push!(optimized, Instruction(OP_CLEAR, 0, 0))
            i = i + 3  # skip SUB, LOOP_START, LOOP_END
        else
            push!(optimized, instrs[i])
            i += 1
        end
    end

    return optimized
end

function run_bf(code::AbstractString, input::AbstractString="")::String
    instrs = compile(code)

    tape = zeros(UInt8, TAPE_SIZE)
    ptr = 1
    ip = 1
    input_idx = 1
    output = IOBuffer()

    while ip <= length(instrs)
        inst = instrs[ip]
        if inst.op == OP_ADD
            tape[ptr] = UInt8(mod(Int(tape[ptr]) + inst.arg, 256))
        elseif inst.op == OP_SUB
            tape[ptr] = UInt8(mod(Int(tape[ptr]) - inst.arg, 256))
        elseif inst.op == OP_LEFT
            new_ptr = ptr - inst.arg
            if new_ptr < 1
                throw(ErrorException("pointer moved left past tape boundary"))
            end
            ptr = new_ptr
        elseif inst.op == OP_RIGHT
            new_ptr = ptr + inst.arg
            if new_ptr > TAPE_SIZE
                throw(ErrorException("pointer moved right past tape boundary"))
            end
            ptr = new_ptr
        elseif inst.op == OP_OUT
            write(output, tape[ptr])
        elseif inst.op == OP_IN
            if input_idx <= length(input)
                tape[ptr] = input[input_idx]
                input_idx += 1
            else
                tape[ptr] = 0
            end
        elseif inst.op == OP_LOOP_START
            if tape[ptr] == 0
                ip = inst.jump
            end
        elseif inst.op == OP_LOOP_END
            if tape[ptr] != 0
                ip = inst.jump
            end
        elseif inst.op == OP_CLEAR
            tape[ptr] = 0
        end
        ip += 1
    end

    return String(take!(output))
end
