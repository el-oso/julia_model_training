# Interval arithmetic — Interval{T<:Real} <: Real
# All arithmetic on Interval{Float64} is allocation-free (verified by tests).

module IntervalArithmetic

export Interval

# ──────────────────────────────────────────────────────────────────────
#  Core struct & constructors
# ──────────────────────────────────────────────────────────────────────
#  _data::Tuple{T,T}: default field ctor is `Interval{T}(data::Tuple{T,T})`.
#  Outer ctor validates then calls it (no recursion).
#  Typed ctor `Interval{T}(lo::Number,hi::Number)` is LESS specific than
#  the default for exact types, so it only fires for cross-type conversion.

struct Interval{T <: Real} <: Real
    _data::Tuple{T, T}
end

# Singleton constructor Interval{T}(x) creates [x, x]
Interval{T}(x::Number) where {T <: Real} =
    Interval{T}((convert(T, x), convert(T, x)))

# Outer constructor: validates lo ≤ hi, delegates to default field ctor
function Interval(lo::Number, hi::Number)
    T = promote_type(typeof(lo), typeof(hi))
    lo_t = convert(T, lo)
    hi_t = convert(T, hi)
    lo_t > hi_t && throw(ArgumentError("lo($lo_t) must be ≤ hi($hi_t)"))
    return Interval{T}((lo_t, hi_t))  # hits default field ctor (no recursion)
end

# Typed constructor: cross-type conversion only (e.g. Int←Float64)
# Less specific than the default field ctor for exact types, so it
# never fires for `Interval{Float64}(1.0,2.0)` — that uses the default.
Interval{T}(lo::Number, hi::Number) where {T <: Real} =
    Interval{T}((convert(T, lo), convert(T, hi)))  # hits default field ctor

# ──────────────────────────────────────────────────────────────────────
#  Accessors — _data is a Tuple{T,T}, unpack via helper
# ──────────────────────────────────────────────────────────────────────

@inline _lo(a::Interval{T}) where {T} = a._data[1]
@inline _hi(a::Interval{T}) where {T} = a._data[2]

Base.getproperty(a::Interval, s::Symbol) = s == :lo ? _lo(a) : s == :hi ? _hi(a) : getfield(a, s)
Base.propertynames(a::Interval) = (:lo, :hi)

# ──────────────────────────────────────────────────────────────────────
#  promote_rule  /  convert
# ──────────────────────────────────────────────────────────────────────

Base.promote_rule(::Type{Interval{T}}, ::Type{Interval{S}}) where {T <: Real, S <: Real} =
    Interval{promote_type(T, S)}

Base.promote_rule(::Type{Interval{T}}, ::Type{S}) where {T <: Real, S <: Real} =
    Interval{promote_type(T, S)}

Base.convert(::Type{Interval{U}}, a::Interval{T}) where {U <: Real, T <: Real} =
    Interval{U}((convert(U, _lo(a)), convert(U, _hi(a))))

# ──────────────────────────────────────────────────────────────────────
#  +  -  *  /  unary -
# ──────────────────────────────────────────────────────────────────────

Base.:+(a::Interval{T}, b::Interval{S}) where {T <: Real, S <: Real} = begin
    U = promote_type(T, S)
    al = convert(U, _lo(a)); ah = convert(U, _hi(a))
    bl = convert(U, _lo(b)); bh = convert(U, _hi(b))
    Interval{U}(al + bl, ah + bh)
end

Base.:(-)(a::Interval{T}, b::Interval{S}) where {T <: Real, S <: Real} = begin
    U = promote_type(T, S)
    al = convert(U, _lo(a)); ah = convert(U, _hi(a))
    bl = convert(U, _lo(b)); bh = convert(U, _hi(b))
    Interval{U}(al - bl, ah - bh)
end

Base.:*(a::Interval{T}, b::Interval{S}) where {T <: Real, S <: Real} = begin
    U = promote_type(T, S)
    al = convert(U, _lo(a)); ah = convert(U, _hi(a))
    bl = convert(U, _lo(b)); bh = convert(U, _hi(b))
    Interval{U}(
        minimum((al * bl, al * bh, ah * bl, ah * bh)),
        maximum((al * bl, al * bh, ah * bl, ah * bh))
    )
end

Base.:/(a::Interval{T}, b::Interval{S}) where {T <: Real, S <: Real} = begin
    U = promote_type(promote_type(T, S), Float64)  # division may be fractional
    bl = convert(U, _lo(b)); bh = convert(U, _hi(b))
    if bl <= zero(U) <= bh
        throw(DivideError())
    end
    al = convert(U, _lo(a)); ah = convert(U, _hi(a))
    Interval{U}(
        minimum((al / bl, al / bh, ah / bl, ah / bh)),
        maximum((al / bl, al / bh, ah / bl, ah / bh))
    )
end

Base.:-(a::Interval{T}) where {T <: Real} =
    Interval{T}(-_hi(a), -_lo(a))

# ── scalar ops ──────────────────────────────────────────────────────────

Base.:+(a::Interval{T}, b::S) where {T <: Real, S <: Real} = begin
    U = promote_type(T, S)
    ub = convert(U, b)
    Interval{U}(convert(U, _lo(a)) + ub, convert(U, _hi(a)) + ub)
end

Base.:+(b::S, a::Interval{T}) where {S <: Real, T <: Real} = a + b

Base.:(-)(a::Interval{T}, b::S) where {T <: Real, S <: Real} = begin
    U = promote_type(T, S)
    ub = convert(U, b)
    Interval{U}(convert(U, _lo(a)) - ub, convert(U, _hi(a)) - ub)
end

Base.:*(a::Interval{T}, b::S) where {T <: Real, S <: Real} = begin
    U = promote_type(T, S)
    ub = convert(U, b)
    al = convert(U, _lo(a)); ah = convert(U, _hi(a))
    if ub >= zero(U)
        Interval{U}(al * ub, ah * ub)
    else
        Interval{U}(ah * ub, al * ub)
    end
end

Base.:*(b::S, a::Interval{T}) where {S <: Real, T <: Real} = a * b

Base.:/(a::Interval{T}, b::S) where {T <: Real, S <: Real} = begin
    U = promote_type(promote_type(T, S), Float64)  # division may be fractional
    ub = convert(U, b)
    if ub == zero(U)
        throw(DivideError())
    end
    Interval{U}(convert(U, _lo(a)) / ub, convert(U, _hi(a)) / ub)
end

# ──────────────────────────────────────────────────────────────────────
#  in / contains
# ──────────────────────────────────────────────────────────────────────

contains(a::Interval, x::Real) = _lo(a) <= x <= _hi(a)
Base.in(x::Real, a::Interval) = contains(a, x)

# ──────────────────────────────────────────────────────────────────────
#  show
# ──────────────────────────────────────────────────────────────────────

Base.show(io::IO, a::Interval) = print(io, "Interval(", _lo(a), ", ", _hi(a), ")")
Base.show(io::IO, ::MIME"text/plain", a::Interval) = show(io, a)

end # module
