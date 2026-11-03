# rle.jl — run-length encoding/decoding. Base only (no external packages).

"""
    iseq(a, b) -> Bool

"Same value" predicate used by `rle`: `true` when `a` and `b` are identical
(`===`), both `NaN`, or `==`-equal.  Unlike plain `==`, it is safe for
`missing` (whose `==` returns `missing`, not a usable truth value) and
treats `NaN` runs as one run.
"""
@inline function iseq(a, b)
    a === b && return true
    return (a == b) === true
end

@inline function iseq(a::T, b::T) where {T <: AbstractFloat}
    a === b && return true
    if isnan(a) || isnan(b)
        return isnan(a) && isnan(b)
    end
    return a == b
end

"""
    rle(v) -> (values, counts)

Run-length encode the consecutive runs of `v` (any `AbstractVector`), returning
`(values, counts)` where `values[i]` is the value of run `i` and `counts[i]` its
length, so `unrle(values, counts) == v` (use `isequal` if `v` contains `missing`
or `NaN`, since `==` on such arrays is not `true`).

Works for any element type — including `missing` and `NaN` (consecutive `NaN`s
form one run) — and for empty vectors, views, and vectors with non-standard
indexing (e.g. `OffsetArray`s).  Returns `(Vector{eltype(v)}, Vector{Int})`.
"""
function rle(v::AbstractVector)
    n = length(v)
    T = eltype(v)
    n == 0 && return (Vector{T}(), Int[])
    values = Vector{T}(undef, n)  # at most n runs; shrink with resize! (O(1))
    counts = Vector{Int}(undef, n)
    k = 0  # runs started so far
    c = 0  # length of the current run
    @inbounds for i in eachindex(v)
        x = v[i]
        if c != 0 && iseq(x, values[k])
            c += 1
            counts[k] = c
        else
            k += 1
            c = 1
            values[k] = x
            counts[k] = 1
        end
    end
    return resize!(values, k), resize!(counts, k)
end

function _bad_count(c)
    c isa Missing && return true
    return c < 0
end

"""
    unrle(values, counts) -> v

Inverse of `rle`: expand the run-length encoding `(values, counts)` back into a
`Vector{eltype(values)}`.  Requires `length(values) == length(counts)` and
non-negative integer counts.
"""
function unrle(values::AbstractVector, counts::AbstractVector)
    length(values) == length(counts) ||
        throw(ArgumentError("values and counts must have the same length"))
    any(_bad_count, counts) &&
        throw(ArgumentError("counts must be non-negative integers"))
    T = eltype(values)
    n = sum(Int, counts; init = 0)
    out = Vector{T}(undef, n)
    i = 1
    @inbounds for (x, c) in zip(values, counts)
        for _ in 1:c
            out[i] = x
            i += 1
        end
    end
    return out
end

# ---------------------------------------------------------------- tests -----
using Test
using OffsetArrays

@testset "rle/unrle" begin
    @testset "basic" begin
        v = [1, 1, 2, 2, 2, 3]
        values, counts = rle(v)
        @test values == [1, 2, 3]
        @test counts == [2, 3, 1]
        @test unrle(values, counts) == v

        @test isequal(rle([7, 7, 7]), ([7], [3]))
        @test isequal(rle([1, 2, 3]), ([1, 2, 3], [1, 1, 1]))
        @test isequal(rle([42]), ([42], [1]))
        @test unrle([42], [1]) == [42]
    end

    @testset "empty" begin
        @test rle(Int[]) == (Int[], Int[])
        @test rle(String[]) == (String[], Int[])
        @test rle(Bool[]) == (Bool[], Int[])
        @test unrle(Int[], Int[]) == Int[]
        @test unrle(String[], Int[]) == String[]
    end

    @testset "missing" begin
        v = [missing, missing, 1, missing, 2, 2]
        values, counts = rle(v)
        @test isequal(values, [missing, 1, missing, 2])
        @test counts == [2, 1, 1, 2]
        @test isequal(unrle(values, counts), v)

        v = [1, missing, missing, 1]
        @test isequal(rle(v), (Union{Missing, Int}[1, missing, 1], [1, 2, 1]))
        @test isequal(unrle(Union{Missing, Int}[1, missing, 1], [1, 2, 1]), v)
    end

    @testset "NaN" begin
        v = [NaN, NaN, 1.0, NaN, 3.0, 3.0]
        values, counts = rle(v)
        @test length(values) == 4
        @test isnan(values[1])
        @test values[2] == 1.0
        @test isnan(values[3])
        @test values[4] == 3.0
        @test counts == [2, 1, 1, 2]
        @test isequal(unrle(values, counts), v)

        # NaN is one run even when the NaN objects are distinct; -0.0 == 0.0
        @test isequal(rle([NaN, 0.0, -0.0]), (Float64[NaN, 0.0], [1, 2]))
        # distinct NaN payloads still form one run
        @test isequal(rle([parse(Float64, "NaN"), parse(Float64, "NaN")]), (Float64[NaN], [2]))
        # Float16 too
        @test isequal(
            rle([Float16(NaN), Float16(NaN), Float16(1)]),
            (Float16[NaN, 1], [2, 1])
        )
    end

    @testset "strings, bools" begin
        v = ["a", "a", "b", "c", "c", "c"]
        values, counts = rle(v)
        @test values == ["a", "b", "c"]
        @test counts == [2, 1, 3]
        @test unrle(values, counts) == v

        @test isequal(rle([true, true, false, true]), (Bool[true, false, true], [2, 1, 1]))
    end

    @testset "views" begin
        v = [5, 5, 1, 1, 1, 9]
        for idx in (2:5, 2:2:6, 6:-1:1)  # sub, strided, reversed
            w = view(v, idx)
            values, counts = rle(w)
            @test isequal(unrle(values, counts), collect(w))
        end
    end

    @testset "offset arrays" begin
        v = OffsetArray([3, 3, 1, 2, 2], -2)  # indices -2:2
        values, counts = rle(v)
        @test values == [3, 1, 2]
        @test counts == [2, 1, 2]
        @test unrle(values, counts) == collect(v)

        w = OffsetArray([7.0, NaN, NaN, 7.0], 10)  # indices 10:13
        values, counts = rle(w)
        @test isequal(values, [7.0, NaN, 7.0])
        @test counts == [1, 2, 1]
        @test isequal(unrle(values, counts), collect(w))
    end

    @testset "type stability" begin
        @test @inferred(rle([1, 2, 2, 3])) isa Tuple{Vector{Int}, Vector{Int}}
        @test @inferred(rle(Float64[])) isa Tuple{Vector{Float64}, Vector{Int}}
        @test @inferred(rle(["a"])) isa Tuple{Vector{String}, Vector{Int}}
        @test @inferred(rle(Union{Missing, Int}[])) isa Tuple{Vector{Union{Missing, Int}}, Vector{Int}}
        @test @inferred(unrle([1, 2], [1, 1])) isa Vector{Int}
        @test @inferred(unrle(Float64[NaN], [2])) isa Vector{Float64}
    end

    @testset "errors" begin
        @test_throws ArgumentError unrle([1, 2], [1])
        @test_throws ArgumentError unrle([1], [-1])
        @test_throws ArgumentError unrle([1], [missing])
    end

    @testset "roundtrip (random)" begin
        v = rand(1:3, 2000)
        @test unrle(rle(v)...) == v
        v = [rand() for _ in 1:500]
        @test isequal(unrle(rle(v)...), v)
        v = [rand(["x", "y", "z"]) for _ in 1:300]
        @test unrle(rle(v)...) == v
        v = [rand(Bool) for _ in 1:400]
        @test unrle(rle(v)...) == v
    end
end

# ------------------------------------------------- benchmark: 10^7 elements -
N = 10_000_000
v = rand(1:50, N)
rle(v)  # warm-up: compile the specialized methods

vals, cnts = rle(v)
res = @timed rle(v)
@info "rle(10^7, $(length(cnts)) runs) : $(round(res.time, digits = 4)) s, $(round(res.bytes / 2^20, digits = 2)) MiB allocated"

res = @timed w = unrle(vals, cnts)
@info "unrle(10^7)                    : $(round(res.time, digits = 4)) s, $(round(res.bytes / 2^20, digits = 2)) MiB allocated"

@assert w == v  # full roundtrip on the 10^7-element array
@info "roundtrip check passed"
