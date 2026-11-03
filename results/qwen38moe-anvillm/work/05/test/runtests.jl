using Test
include("../src/Interval.jl")
using .IntervalArithmetic

# ──────────────────────────────────────────────────────────────────────
#  Constructor
# ──────────────────────────────────────────────────────────────────────

@test Interval(1, 2).lo == 1
@test Interval(1, 2).hi == 2
@test Interval(1.0, 2.0) isa Interval{Float64}
@test Interval(Int32(1), Int32(2)) isa Interval{Int32}

# lo > hi  →  ArgumentError
@test_throws ArgumentError Interval(2, 1)
@test_throws ArgumentError Interval(2.0, 1.0)

# ──────────────────────────────────────────────────────────────────────
#  promote_rule / element type
# ──────────────────────────────────────────────────────────────────────

# Interval(1,2) + 1.5  →  Interval{Float64}
r = Interval(1, 2) + 1.5
@test r isa Interval{Float64}
@test r.lo ≈ 2.5
@test r.hi ≈ 3.5

# Interval * Interval
r = Interval(1, 2) * Interval(0.5, 1.0)
@test r isa Interval{Float64}
@test r.lo ≈ 0.5
@test r.hi ≈ 2.0

# Int + Interval
@test Interval(1, 2) + 3 == Interval(4, 5)

# Mixed Int × Float → Float
r = Interval(1, 2) * 2.5
@test r isa Interval{Float64}
@test r.lo ≈ 2.5
@test r.hi ≈ 5.0

# ──────────────────────────────────────────────────────────────────────
#  No allocation on Interval{Float64}
# ──────────────────────────────────────────────────────────────────────

a = Interval{Float64}(1, 2)
b = Interval{Float64}(0.5, 1.0)

@test @allocated(a + b) == 0
@test @allocated(a - b) == 0
@test @allocated(a * b) == 0
@test @allocated(a / b) == 0
@test @allocated(-a) == 0
@test @allocated(a + 1.5) == 0
@test @allocated(a * 2.0) == 0
@test @allocated(a / 2.0) == 0

# ──────────────────────────────────────────────────────────────────────
#  Division by interval containing zero
# ──────────────────────────────────────────────────────────────────────

@test_throws DivideError Interval(1, 2) / Interval(-1, 1)   # lo < 0 < hi
@test_throws DivideError Interval(1, 2) / Interval(-1, 0)   # contains 0
@test_throws DivideError Interval(1, 2) / Interval(0, 1)    # contains 0

# division by zero scalar
@test_throws DivideError Interval(1, 2) / 0

# ──────────────────────────────────────────────────────────────────────
#  in / contains
# ──────────────────────────────────────────────────────────────────────

a = Interval(0, 5)
@test IntervalArithmetic.contains(a, 3)
@test IntervalArithmetic.contains(a, 0)
@test IntervalArithmetic.contains(a, 5)
@test !IntervalArithmetic.contains(a, -1)
@test !IntervalArithmetic.contains(a, 6)

@test 3 in a
@test 0 in a
@test 5 in a
@test !(-1 in a)
@test !(6 in a)

# ──────────────────────────────────────────────────────────────────────
#  show
# ──────────────────────────────────────────────────────────────────────

io = IOBuffer()
show(io, Interval(1, 2))
@test String(take!(io)) == "Interval(1, 2)"

# ──────────────────────────────────────────────────────────────────────
#  Unary minus
# ──────────────────────────────────────────────────────────────────────

@test -Interval(3, 7) == Interval(-7, -3)
@test -Interval{Float64}(1.5, 4.0) == Interval{Float64}(-4.0, -1.5)

# ──────────────────────────────────────────────────────────────────────
#  Arithmetic identities
# ──────────────────────────────────────────────────────────────────────

a = Interval(2, 5)
b = Interval(1, 3)

# a + (-a) contains 0
r = a + (-a)
@test IntervalArithmetic.contains(r, 0)
@test r.lo == -3  # 2 + (-5)
@test r.hi == 3   # 5 + (-2)

# a / a ⊇ [1, 1]
r = a / a
@test IntervalArithmetic.contains(r, 1.0)
@test r.lo ≈ 0.4   # 2/5
@test r.hi ≈ 2.5   # 5/2

# ──────────────────────────────────────────────────────────────────────
#  Mixed-type propagation
# ──────────────────────────────────────────────────────────────────────

# Float32 × Float64 → Float64
r = Interval(Float32(1), Float32(2)) * Interval{Float64}(0.5, 1.0)
@test r isa Interval{Float64}
@test r.lo ≈ 0.5
@test r.hi ≈ 2.0

# Int × Int → Int
r = Interval(1, 2) * Interval(3, 4)
@test r isa Interval{Int}
@test r.lo == 3
@test r.hi == 8

# ──────────────────────────────────────────────────────────────────────
#  Edge cases
# ──────────────────────────────────────────────────────────────────────

# Singleton interval
s = Interval(3, 3)
@test -s == Interval(-3, -3)
@test s + s == Interval(6, 6)
@test s * s == Interval(9, 9)
@test s / s == Interval(1, 1)

# Negative interval
n = Interval(-5, -1)
@test n * n == Interval(1, 25)
@test n / n == Interval(1 / 5, 5)

