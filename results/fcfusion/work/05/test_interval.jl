using .Main
include("interval.jl")

# Constructor validation
try
    Interval(3, 1)
    @error "should have thrown for lo > hi"
catch e
    @assert isa(e, ArgumentError)
end

# Basic construction
a = Interval(1, 2)
b = Interval(3, 4)
c = Interval(1.5, 2.5)
d = Interval(0.5, 1.0)
pt = Interval(5, 5)  # degenerate interval

# Addition
r = a + b
@assert r.lo == 4 && r.hi == 6

r = a + 1.5
@assert typeof(r) == Interval{Float64}
@assert r.lo == 2.5 && r.hi == 3.5

r = 1.5 + a
@assert typeof(r) == Interval{Float64}
@assert r.lo == 2.5 && r.hi == 3.5

r = c + d
@assert r.lo == 2.0 && r.hi == 3.5

# Subtraction
r = a - b
@assert r.lo == -3 && r.hi == -1

r = a - 1.5
@assert typeof(r) == Interval{Float64}
@assert r.lo == -0.5 && r.hi == 0.5

r = 1.5 - a
@assert typeof(r) == Interval{Float64}
@assert r.lo == -0.5 && r.hi == 0.5

# Unary minus
r = -a
@assert r.lo == -2 && r.hi == -1

r = -c
@assert r.lo == -2.5 && r.hi == -1.5

# Multiplication
r = a * b
@assert r.lo == 3 && r.hi == 8

r = a * 2.0
@assert typeof(r) == Interval{Float64}
@assert r.lo == 2.0 && r.hi == 4.0

r = 2.0 * a
@assert typeof(r) == Interval{Float64}
@assert r.lo == 2.0 && r.hi == 4.0

r = a * -2.0
@assert r.lo == -4.0 && r.hi == -2.0

# Multiplication with negative interval
neg = Interval(-3, -1)
r = a * neg
@assert r.lo == -6 && r.hi == -1

# Division
r = a / 2.0
@assert r.lo == 0.5 && r.hi == 1.0

r = a / -2.0
@assert r.lo == -1.0 && r.hi == -0.5

r = a / b
@assert r.lo == 0.25 && r.hi == 2/3

# Division by interval containing zero throws
try
    a / Interval(-1, 1)
    @error "should have thrown for division by interval containing zero"
catch e
    @assert isa(e, DivideError)
end

# Division by zero scalar throws
try
    a / 0.0
    @error "should have thrown for division by zero"
catch e
    @assert isa(e, DivideError)
end

# in
@assert 1.5 in a
@assert 1.0 in a
@assert 2.0 in a
@assert !(0.0 in a)
@assert !(3.0 in a)
@assert 5 in pt

# show
@assert string(a) == "[1, 2]"
@assert string(c) == "[1.5, 2.5]"
@assert string(pt) == "[5, 5]"

# Type promotion: Interval(1, 2) + 1.5 -> Interval{Float64}
r1 = Interval(1, 2) + 1.5
@assert typeof(r1) == Interval{Float64}
@assert r1.lo == 2.5 && r1.hi == 3.5

# Type promotion: Interval(1, 2) * Interval(0.5, 1.0) -> Interval{Float64}
r2 = Interval(1, 2) * Interval(0.5, 1.0)
@assert typeof(r2) == Interval{Float64}
@assert r2.lo == 0.5 && r2.hi == 2.0

# Non-allocating operations on Interval{Float64}
ia = Interval(1.0, 2.0)
ib = Interval(3.0, 4.0)

function check_alloc(name, expr)
    allocs = @allocated expr
    if allocs != 0
        print("FAIL: $name allocated $allocs bytes\n")
        return false
    end
    return true
end

ok = true
ok &= check_alloc("addition", ia + ib)
ok &= check_alloc("subtraction", ia - ib)
ok &= check_alloc("multiplication", ia * ib)
ok &= check_alloc("division", ia / ib)
ok &= check_alloc("unary minus", -ia)
ok &= check_alloc("addition with scalar", ia + 1.5)
ok &= check_alloc("multiplication with scalar", ia * 2.0)
if !ok
    error("allocation tests failed")
end

print("All tests passed.\n")
