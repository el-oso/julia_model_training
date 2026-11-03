struct Interval{T<:Real} <: Real
    lo::T
    hi::T
    function Interval(lo::T, hi::T) where T<:Real
        if lo > hi
            throw(ArgumentError("lo must be ≤ hi"))
        end
        new{T}(lo, hi)
    end
end

# Convenience constructor that infers the element type
Interval(lo::Real, hi::Real) = Interval(promote(lo, hi)...)

import Base: +, -, *, /, -, in, show, promote_rule, convert

# Promotion rules
promote_rule(::Type{Interval{T}}, ::Type{Interval{S}}) where {T<:Real, S<:Real} =
    Interval{promote_type(T, S)}
promote_rule(::Type{Interval{T}}, ::Type{S}) where {T<:Real, S<:Real} =
    Interval{promote_type(T, S)}

# Conversion
convert(::Type{Interval{T}}, x::Real) where T = Interval(T(x), T(x))
convert(::Type{Interval{T}}, x::Interval{S}) where {T, S} = Interval(T(x.lo), T(x.hi))

# Addition
function +(a::Interval, b::Interval)
    return Interval(a.lo + b.lo, a.hi + b.hi)
end

function +(a::Interval, b::Real)
    return Interval(a.lo + b, a.hi + b)
end

+(a::Real, b::Interval) = b + a

# Subtraction
function -(a::Interval, b::Interval)
    return Interval(a.lo - b.hi, a.hi - b.lo)
end

function -(a::Interval, b::Real)
    return Interval(a.lo - b, a.hi - b)
end

function -(a::Real, b::Interval)
    return Interval(a - b.hi, a - b.lo)
end

-(a::Interval) = Interval(-a.hi, -a.lo)

# Multiplication
function *(a::Interval, b::Interval)
    p1 = a.lo * b.lo
    p2 = a.lo * b.hi
    p3 = a.hi * b.lo
    p4 = a.hi * b.hi
    return Interval(min(p1, p2, p3, p4), max(p1, p2, p3, p4))
end

function *(a::Interval, b::Real)
    p1 = a.lo * b
    p2 = a.hi * b
    return Interval(min(p1, p2), max(p1, p2))
end

*(a::Real, b::Interval) = b * a

# Division
function /(a::Interval, b::Interval)
    if b.lo <= 0 && 0 <= b.hi
        throw(DivideError())
    end
    q1 = a.lo / b.lo
    q2 = a.lo / b.hi
    q3 = a.hi / b.lo
    q4 = a.hi / b.hi
    return Interval(min(q1, q2, q3, q4), max(q1, q2, q3, q4))
end

function /(a::Interval, b::Real)
    if b == 0
        throw(DivideError())
    end
    q1 = a.lo / b
    q2 = a.hi / b
    return Interval(min(q1, q2), max(q1, q2))
end

# Membership test
in(x::Real, interval::Interval) = interval.lo <= x <= interval.hi

# Display
function show(io::IO, interval::Interval)
    print(io, "[", interval.lo, ", ", interval.hi, "]")
end
