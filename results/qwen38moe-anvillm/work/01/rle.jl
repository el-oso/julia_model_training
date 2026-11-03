using Test, Random

# ── rle ──────────────────────────────────────────────────────────────────────────
"""
    rle(v) -> (values, counts)

Run-length encoding of any `AbstractVector`.  Returns two `Vector`s of type
`(eltype(v), Int)` for consecutive runs (equal by `isequal`, so `NaN==NaN`
and `missing==missing` hold).  Handles empty input, views, OffsetArrays, etc.

Example:
    rle([1,1,2,2,2,3,3])  #  →  ([1,2,3], [2,3,2])
"""
function rle(v::AbstractVector)
    n = length(v)
    n == 0 && return (eltype(v)[], Int[])
    nr = 1  # at least one run (n > 0)
    prev = @inbounds v[firstindex(v)]
    for i in firstindex(v)+1:lastindex(v)
        cur = @inbounds v[i]
        nr += !isequal(cur, prev)
        prev = cur
    end
    vals = Vector{eltype(v)}(undef, nr)
    cts  = Vector{Int}(undef, nr)
    @inbounds val = v[firstindex(v)]
    j = 1
    vals[1] = val; cts[1] = 1
    for i in firstindex(v)+1:lastindex(v)
        @inbounds cur = v[i]
        if isequal(cur, val)
            @inbounds cts[j] += 1
        else
            @inbounds val = cur
            j += 1
            vals[j] = val
            cts[j]  = 1
        end
    end
    return vals, cts
end

# ── unrle ────────────────────────────────────────────────────────────────────────
"""
    unrle(values, counts) -> Vector

Invert `rle`: `values` and `counts` must be equal-length `AbstractVector`s and
`counts` entries must be non-negative integers (0 yields an empty result).

Example:
    unrle([1,2,3], [2,3,2])  #  →  [1,1,2,2,2,3,3]
"""
function unrle(values::AbstractVector, counts::AbstractVector)
    n = length(counts)
    total = zero(eltype(counts))
    for c in counts
        total += c
    end
    T = eltype(values)
    out = Vector{T}(undef, total)
    i = firstindex(out)
    @inbounds for k in eachindex(counts)
        cnt = counts[k]
        v   = values[k]
        for _ in 1:cnt
            out[i] = v
            i += 1
        end
    end
    return out
end

# ── tests ────────────────────────────────────────────────────────────────────────

# Empty
@test rle(Int[]) == (Int[], Int[])
@test rle(Float64[]) == (Float64[], Int[])
@test unrle(Int[], Int[]) == Int[]
@test unrle(Float64[], Int[]) == Float64[]

# Single element
@test rle([42]) == ([42], [1])
@test unrle([42], [1]) == [42]

# No runs (all different)
@test rle([1,2,3]) == ([1,2,3], [1,1,1])
@test unrle([1,2,3], [1,1,1]) == [1,2,3]

# Single run
@test rle([7,7,7]) == ([7], [3])
@test unrle([7], [3]) == [7,7,7]

# Mixed
@test rle([1,1,2,2,2,3,3]) == ([1,2,3], [2,3,2])
@test unrle([1,2,3], [2,3,2]) == [1,1,2,2,2,3,3]

# NaN values
@test isequal(rle([NaN, NaN, 1.0, NaN]), ([NaN, 1.0, NaN], [2, 1, 1]))
@test isequal(unrle([NaN, 1.0, NaN], [2, 1, 1]), [NaN, NaN, 1.0, NaN])

# missing
@test isequal(rle([missing, missing, 1]), ([missing, 1], [2, 1]))
@test isequal(unrle([missing, 1], [2, 1]), [missing, missing, 1])

# View
v = view([1,1,2,2,2,3,3], 2:6)  # [1,2,2,2,3]
@test rle(v) == ([1,2,3], [1,3,1])

# OffsetArray
using OffsetArrays
oa = OffsetArray([1,1,1,2,2], 5)
@test rle(oa) == ([1,2], [3,2])

# Zero-count entries (should produce empty output for that run)
@test unrle([1,2,3], [0, 3, 0]) == [2,2,2]

# Large single value
@test rle([3.14159, 3.14159]) == ([3.14159], [2])
@test unrle([3.14159], [2]) == [3.14159, 3.14159]

# ── benchmark on 10^7 elements ──────────────────────────────────────────────────
println("\n=== Benchmark on 10^7 elements ===")

let
    # Build a vector with ~1000 distinct runs (long runs + occasional short runs)
    n = 10^7
    # Pattern: 80% runs of length 1, 20% runs of length 20 → ~1000 runs
    rle_vec = Vector{Int64}(undef, n)
    i = 1
    val = 0
    runs = 0
    while i <= n
        if rand() < 0.2
            len = 20
        else
            len = 1
        end
        val += 1
        runs += 1
        for _ in 1:min(len, n - i + 1)
            rle_vec[i] = val
            i += 1
        end
    end
    println("  Elements: ", length(rle_vec), "  Runs: ", runs)

    # warm up
    rle(rle_vec)

    println("  rle():")
    @time vals, cts = rle(rle_vec)
    println("    vals length = $(length(vals)), cts length = $(length(cts))")
    @assert length(vals) == length(cts) == runs

    println("  unrle():")
    @time w = unrle(vals, cts)
    println("    result length = $(length(w))")
    @assert length(w) == n

    # roundtrip check (sample indices)
    Random.seed!(42)
    for _ in 1:5
        idx = rand(1:n)
        @assert w[idx] == rle_vec[idx]
    end
    println("  roundtrip: all checked ✓")
end

println("\nDone.")
