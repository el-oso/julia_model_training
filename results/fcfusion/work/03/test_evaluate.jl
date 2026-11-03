include("evaluate.jl")

# Basic arithmetic
@assert evaluate("2 + 3") == 5.0
@assert evaluate("10 - 4") == 6.0
@assert evaluate("3 * 4") == 12.0
@assert evaluate("10 / 2") == 5.0

# Precedence
@assert evaluate("2 + 3 * 4") == 14.0
@assert evaluate("2 * 3 + 4") == 10.0
@assert evaluate("10 / 2 + 3") == 8.0

# Exponentiation (right-associative)
@assert evaluate("2 ^ 3") == 8.0
@assert evaluate("2 ^ 3 ^ 2") == 512.0  # 2^(3^2) = 2^9
@assert evaluate("3 ^ 2 ^ 3") == 6561.0  # 3^(2^3) = 3^8

# Unary minus and exponentiation precedence
@assert evaluate("-2 ^ 2") == -4.0       # -(2^2)
@assert evaluate("2 ^ -3") == 0.125      # 2^(-3)
@assert evaluate("-2 ^ -2") == -0.25     # -(2^(-2))

# Parentheses
@assert evaluate("(2 + 3) * 4") == 20.0
@assert evaluate("2 * (3 + 4)") == 14.0
@assert evaluate("((2 + 3) * (4 - 1))") == 15.0

# Decimals
@assert evaluate("3.14 * 2") == 6.28
@assert evaluate(".5 + .5") == 1.0
@assert evaluate("2.5 * 4") == 10.0

# Whitespace
@assert evaluate("  2 + 3  ") == 5.0
@assert evaluate("2+3") == 5.0
@assert evaluate("2 +3") == 5.0

# Complex expression
@assert evaluate("2 + 3 * 4 ^ 2 - 6 / 3") == 48.0  # 2 + 48 - 2

# Multiple unary minus
@assert evaluate("--5") == 5.0
@assert evaluate("-(-3)") == 3.0

# Error cases
try
    evaluate("")
    @assert false "Should have thrown"
catch e
    @assert occursin("position", string(e))
end

try
    evaluate("2 +")
    @assert false "Should have thrown"
catch e
    @assert occursin("position", string(e))
end

try
    evaluate("2 *")
    @assert false "Should have thrown"
catch e
    @assert occursin("position", string(e))
end

try
    evaluate("2 ^")
    @assert false "Should have thrown"
catch e
    @assert occursin("position", string(e))
end

try
    evaluate("2 / 0")
    @assert false "Should have thrown"
catch e
    @assert occursin("zero", string(e))
end

try
    evaluate("(2 + 3")
    @assert false "Should have thrown"
catch e
    @assert occursin("position", string(e))
end

try
    evaluate("2 + 3)")
    @assert false "Should have thrown"
catch e
    @assert occursin("position", string(e))
end

try
    evaluate("2 & 3")
    @assert false "Should have thrown"
catch e
    @assert occursin("position", string(e))
end

try
    evaluate("12a34")
    @assert false "Should have thrown"
catch e
    @assert occursin("position", string(e))
end

# Performance test: 10^5 character expression
n = 100000
expr = join([string(i % 10) for i in 1:n], " + ")
t = time()
result = evaluate(expr)
elapsed = time() - t
println("Evaluated 10^5-char expression in $(elapsed*1000) ms")
@assert elapsed < 5.0 "Too slow: $(elapsed) seconds"

println("All tests passed!")
