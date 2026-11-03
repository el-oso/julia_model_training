# test_evaluate.jl — correctness, error handling, depth, fuzz, and benchmarks.
using Random
include("evaluate.jl")

function run_tests()
    failures = String[]
    npass = Ref(0)
    function check(desc, cond)
        if cond
            npass[] += 1
        else
            push!(failures, desc)
            println("  FAILED: $desc")
        end
        cond
    end

    # ---------------- basic correctness ----------------
    check("1+2", evaluate("1+2") == 3.0)
    check("2+3*4", evaluate("2+3*4") == 14.0)
    check("2*3+4", evaluate("2*3+4") == 10.0)
    check("(2+3)*4", evaluate("(2+3)*4") == 20.0)
    check("10/2/5", evaluate("10/2/5") == 1.0)          # left-assoc
    check("100/10/2", evaluate("100/10/2") == 5.0)
    check("2^3", evaluate("2^3") == 8.0)
    check("2^3^2 right-assoc", evaluate("2^3^2") == 512.0)
    check("-2^2 == -4", evaluate("-2^2") == -4.0)
    check("(-2)^2 == 4", evaluate("(-2)^2") == 4.0)
    check("2^-2", evaluate("2^-2") == 0.25)
    check("-2*3", evaluate("-2*3") == -6.0)
    check("2*-3", evaluate("2*-3") == -6.0)
    check("-2^3^2", evaluate("-2^3^2") == -512.0)
    check("2^3^2-2", evaluate("2^3^2-2") == 510.0)
    check("1+2*3^2", evaluate("1+2*3^2") == 19.0)
    check("2.5+0.25", evaluate("2.5+0.25") == 2.75)
    check(".5", evaluate(".5") == 0.5)
    check("12.", evaluate("12.") == 12.0)
    check("0.1+0.2", evaluate("0.1+0.2") == 0.1 + 0.2)
    check("spaces", evaluate("  1 + 2 * 3 \t\n ") == 7.0)
    check("--2", evaluate("--2") == 2.0)
    check("- - 2", evaluate("- - 2") == 2.0)
    check("-(2+3)", evaluate("-(2+3)") == -5.0)
    check("2^-(1+1)", evaluate("2^-(1+1)") == 0.25)
    check("2^--3", evaluate("2^--3") == 8.0)
    check("2^(1+1)^2", evaluate("2^(1+1)^2") == 16.0)
    check("-(1+2)*3", evaluate("-(1+2)*3") == -9.0)
    check("2^-3*4", evaluate("2^-3*4") == 0.5)
    check("6/-2", evaluate("6/-2") == -3.0)
    check("2.5e0-rejected", let
        try evaluate("2.5e0"); false
        catch e; e isa ParseError; end
    end)
    check("sqrt via ^0.5", evaluate("4^0.5") == 2.0)
    check("1/0 == Inf", evaluate("1/0") == Inf)
    check("0.0^0 == 1", evaluate("0.0^0") == 1.0)

    # ---------------- error handling ----------------
    function errpos(s)
        try
            evaluate(s)
            nothing
        catch e
            @assert e isa ParseError "expected ParseError for $(repr(s)), got $e"
            (e.pos, e.msg)
        end
    end

    p, m = errpos("")
    check("empty: pos", p == 1)
    check("empty: msg mentions empty", occursin("empty", m))
    check("empty: msg has position", occursin("position 1", m))

    p, m = errpos("   ")
    check("whitespace-only: pos", p == 1)

    p, m = errpos("x+1")
    check("'x+1' pos", p == 1)
    check("'x+1' names char", occursin("\"x\"", m) && occursin("position 1", m))

    p, m = errpos("1+x")
    check("'1+x' pos", p == 3)

    p, m = errpos("1+é")
    check("'1+é' pos (char index)", p == 3)
    check("'1+é' names char", occursin("é", m))

    p, m = errpos("1+")
    check("'1+' pos", p == 3)
    check("'1+' names problem", occursin("number", m) || occursin("operand", m))

    p, m = errpos("1+*2")
    check("'1+*2' pos", p == 3)

    p, m = errpos("2^")
    check("'2^' pos", p == 3)

    p, m = errpos("(1+2")
    check("'(1+2' pos", p == 5)
    check("'(1+2' mentions ')'", occursin("')'", m))

    p, m = errpos("1+2)")
    check("'1+2)' pos", p == 4)

    p, m = errpos("1 2")
    check("'1 2' pos", p == 3)

    p, m = errpos("()")
    check("'()' pos", p == 2)

    p, m = errpos("1..2")
    check("'1..2' pos", p == 3)

    p, m = errpos("1.2.3")
    check("'1.2.3' pos", p == 4)

    p, m = errpos("+2")
    check("' +2' pos", p == 1)

    p, m = errpos("2**3")
    check("'2**3' pos", p == 3)

    # 1/0 is not an error (Float64 division gives Inf)
    r = errpos("1/0")
    check("1/0 no error", r === nothing)

    # every error message must name the problem AND contain the position
    for s in ["", "x", "1+", "1+*2", "(1", "1)", "1 2", "2^", "()", "1..2", "1.2.3", "+2", "2**3", "a b"]
        r = errpos(s)
        if r !== nothing
            p, m = r
            check("msg+pos for $(repr(s))", occursin("position $p", m))
        end
    end

    # ---------------- deep nesting (stack safety) ----------------
    for k in [1_000, 5_000, 10_000, 25_000, 50_000]
        s = "("^k * "1" * ")"^k
        v = evaluate(s)
        check("deep parens k=$k", v == 1.0 && length(s) == 2k + 1)
    end
    # deep ^ chain (iterative path)
    check("2^2^2", evaluate("2^2^2") == 256.0)
    chain = "2" * "^2"^49999   # 10^5 chars, 50k right-associative ^'s -> Inf
    v = evaluate(chain)
    check("deep ^ chain 10^5 chars", length(chain) == 99999 && isinf(v) && v > 0)

    # ---------------- fuzz against Julia's own parser ----------------
    rng = MersenneTwister(42)
    function rand_expr(rng, depth)
        if depth <= 0 || rand(rng) < 0.3
            if rand(rng) < 0.5
                return string(round(Float64, rand(rng) * 100; digits=3))
            end
            return string(rand(rng, 0:99))
        end
        op = rand(rng, ["+", "-", "*", "/"])
        a = rand_expr(rng, depth - 1)
        b = rand_expr(rng, depth - 1)
        r = rand(rng)
        if r < 0.15
            return "($a$op$b)"
        elseif r < 0.3
            return "-$a"
        elseif r < 0.4
            # powers with small integer exponents to keep values in range
            return "($a)^(2)"
        else
            return "$a$op$b"
        end
    end
    fuzz_fail = 0
    for trial in 1:2000
        s = rand_expr(rng, 3)
        try
            expected = eval(Meta.parse(s))::Float64
        catch
            continue  # reference rejected it (e.g. int div-by-zero); skip
        end
        try
            got = evaluate(s)
        catch e
            @show s
            @show e
            fuzz_fail += 1
            continue
        end
        if !(got == expected || (isnan(got) && isnan(expected)) ||
             (isinf(got) && isinf(expected) && sign(got) == sign(expected)))
            @show s
            @show (got, expected)
            fuzz_fail += 1
        end
    end
    check("fuzz 2000 random expressions", fuzz_fail == 0)

    # targeted fuzz: mixed powers/unary minus
    fuzz_fail = 0
    for trial in 1:2000
        a = string(rand(rng, 0:9))
        b = string(rand(rng, 0:9))
        c = string(rand(rng, 0:9))
        s = "$(rand(rng,["", "-"]))$a^$(rand(rng,["", "-"]))$b^$(rand(rng,["", "-"]))$c"
        try
            expected = eval(Meta.parse(s))::Float64
        catch
            continue
        end
        try
            got = evaluate(s)
        catch e
            @show s
            @show e
            fuzz_fail += 1
            continue
        end
        if !(got == expected || (isinf(got) && isinf(expected) && sign(got) == sign(expected)))
            @show s
            @show (got, expected)
            fuzz_fail += 1
        end
    end
    check("fuzz powers/unary 2000", fuzz_fail == 0)

    println("\npassed=$(npass[])  failed=$(length(failures))")
    return length(failures)
end

nfail = run_tests()
nfail > 0 && exit(1)
