# Run-Length Encoding in Julia
# rle(v) → (values, counts)
# unrle(values, counts) → reconstructed vector

using Test

# Equality for RLE: same type + isequal (handles NaN, missing)
function rle_eq(x, y)
    typeof(x) == typeof(y) && isequal(x, y)
end

function rle(v::AbstractVector)
    n = length(v)
    if n == 0
        return (Vector{eltype(v)}(), Vector{Int}())
    end

    # Allocate worst-case (every element is its own run)
    values = Vector{eltype(v)}(undef, n)
    counts = Vector{Int}(undef, n)

    # Use iteration, not index arithmetic, to support OffsetArrays/views
    it = iterate(v)
    if it === nothing
        return (values, counts)
    end
    first_val, state = it
    values[1] = first_val
    counts[1] = 1
    num_runs = 1

    while true
        it = iterate(v, state)
        if it === nothing
            break
        end
        val, state = it
        if rle_eq(val, values[num_runs])
            counts[num_runs] += 1
        else
            num_runs += 1
            values[num_runs] = val
            counts[num_runs] = 1
        end
    end

    resize!(values, num_runs)
    resize!(counts, num_runs)
    return (values, counts)
end

function unrle(values::AbstractVector, counts::AbstractVector{<:Integer})
    @assert length(values) == length(counts) "values and counts must have same length"

    total = 0
    for c in counts
        @assert c >= 1 "counts must be positive"
        total += c
    end

    result = Vector{eltype(values)}(undef, total)
    idx = 1
    for i in 1:length(values)
        c = counts[i]
        val = values[i]
        @inbounds for j in 0:c-1
            result[idx + j] = val
        end
        idx += c
    end
    return result
end

# ── Tests ────────────────────────────────────────────────────────────────────

# Basic
vals, cnts = rle([1, 1, 2, 2, 2, 3])
@test vals == [1, 2, 3]
@test cnts == [2, 3, 1]

@test unrle([1, 2, 3], [2, 3, 1]) == [1, 1, 2, 2, 2, 3]

# Empty
@test rle(Int[]) == (Int[], Int[])
@test unrle(Int[], Int[]) == Int[]

# Single element
vals, cnts = rle([42])
@test vals == [42]
@test cnts == [1]
@test unrle(vals, cnts) == [42]

# All same
vals, cnts = rle([7, 7, 7, 7])
@test vals == [7]
@test cnts == [4]

# Roundtrip on varied data
original = [1, 1, 2, 2, 2, 1, 3, 3, 4, 4, 4, 4, 5]
vals, cnts = rle(original)
@test unrle(vals, cnts) == original

# NaN handling (NaN == NaN is false, but should be one run)
vals, cnts = rle([NaN, NaN, 1.0, 1.0, NaN])
@test length(vals) == 3
@test cnts == [2, 2, 1]
@test isnan(vals[1]) && isnan(vals[3])

# missing handling
vals, cnts = rle([missing, missing, 1, 1, missing])
@test isequal(vals, [missing, 1, missing])
@test cnts == [2, 2, 1]

# Char
vals, cnts = rle(["a", "a", "b", "b", "b", "a"])
@test vals == ["a", "b", "a"]
@test cnts == [2, 3, 1]

# Bool
vals, cnts = rle([true, true, false, true, true, true])
@test vals == [true, false, true]
@test cnts == [2, 1, 3]

# Tuple elements
vals, cnts = rle([(1, 2), (1, 2), (3, 4)])
@test vals == [(1, 2), (3, 4)]
@test cnts == [2, 1]

# Views
v = [1, 1, 2, 2, 2, 3, 3]
subview = view(v, 2:5)  # [1, 2, 2, 2]
vals, cnts = rle(subview)
@test vals == [1, 2]
@test cnts == [1, 3]

# OffsetArray
using OffsetArrays
oa = OffsetArray([1, 1, 2, 2, 3], -2)
vals, cnts = rle(oa)
@test vals == [1, 2, 3]
@test cnts == [2, 2, 1]

# Type stability checks
rle_result = rle([1, 2, 3])
@test eltype(rle_result[1]) == Int
@test eltype(rle_result[2]) == Int

rle_float = rle([1.0, 2.0])
@test eltype(rle_float[1]) == Float64
@test eltype(unrle([1, 2], [1, 1])) == Int
@test eltype(unrle([1.0, 2.0], [1, 1])) == Float64

println("All tests passed!")

# ── Benchmark ────────────────────────────────────────────────────────────────

# Create 10^7 element vector with ~1000 runs of 10^4 each
function make_benchmark_data(n, runs)
    data = Vector{Int}(undef, n)
    per_run = n ÷ runs
    val = 1
    idx = 1
    for _ in 1:runs
        for j in 0:per_run-1
            if idx + j <= n
                data[idx + j] = val
            end
        end
        idx += per_run
        val += 1
    end
    return data
end

big_data = make_benchmark_data(10_000_000, 1000)

# Time rle
t1 = time_ns()
vals, cnts = rle(big_data)
t2 = time_ns()
println("rle 10^7 elements (1000 runs): $(round((t2-t1)/1e6, digits=2)) ms")
println("  → $(length(vals)) runs")

# Time unrle
t3 = time_ns()
reconstructed = unrle(vals, cnts)
t4 = time_ns()
println("unrle back to 10^7: $(round((t4-t3)/1e6, digits=2)) ms")
println("  roundtrip correct: $(reconstructed == big_data)")

# Worst case: no runs (every element different)
t5 = time_ns()
vals2, cnts2 = rle(1:10_000_000)
t6 = time_ns()
println("rle 10^7 unique elements: $(round((t6-t5)/1e6, digits=2)) ms")
