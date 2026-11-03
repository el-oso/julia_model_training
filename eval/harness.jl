# Runs one task in this process: harness.jl <code.jl> <check.jl> [dep ...]
# Exit codes: 0 pass, 10 solution failed to evaluate, 11 check failed.
using Test
include(joinpath(@__DIR__, "helpers.jl"))

code_file, check_file = ARGS[1], ARGS[2]
deps = ARGS[3:end]
code = read(code_file, String)
check = read(check_file, String)

m = Module(:Sol)
Core.eval(m, :(using Test))
Core.eval(m, :(using Main.EvalHelpers))
Core.eval(m, :(const SOLUTION_SOURCE = $code))
# Records `@testitem` blocks without running them, so checks can inspect their structure.
Core.eval(
    m, quote
        const TESTITEMS = NamedTuple[]
        macro testitem(name, args...)
            push!(TESTITEMS, (name = name, opts = args[1:(end - 1)], body = args[end]))
            return nothing
        end
    end
)

try
    include_string(m, code, "solution.jl")
catch e
    println("EVAL ERROR: ", sprint(showerror, e, catch_backtrace(); context = :limit => true))
    exit(10)
end

for d in deps
    Core.eval(m, :(using $(Symbol(d))))
end

try
    @testset "check" begin
        include_string(m, check, "check.jl")
    end
catch e
    e isa Test.TestSetException || println("CHECK ERROR: ", sprint(showerror, e))
    exit(11)
end
