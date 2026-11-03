# Sliding window iterator yielding views (no per-window allocation)

struct Windows{V<:AbstractVector}
    vec::V
    k::Int
end

function windows(v::AbstractVector, k::Int)
    if k <= 0
        throw(ArgumentError("window size k must be positive, got $k"))
    end
    Windows(v, k)
end

# Number of windows
Base.length(w::Windows) = max(0, length(w.vec) - w.k + 1)

# Type of each yielded view
Base.eltype(w::Windows) = typeof(view(w.vec, 1:w.k))

# Support length() and collect()
Base.IteratorSize(::Type{Windows}) = Base.HasLength()
Base.IteratorEltype(::Type{Windows}) = Base.HasEltype()

# Yield each window as a view
function Base.iterate(w::Windows, state::Int=1)
    if state > length(w)
        return nothing
    end
    start = firstindex(w.vec) + state - 1
    stop = start + w.k - 1
    win = @view w.vec[start:stop]
    return (win, state + 1)
end

# --- Demo ---
using OffsetArrays

# Basic usage
v = [1, 2, 3, 4, 5]
for w in windows(v, 3)
    println(w)
end

# Length / collect support
println("length: ", length(windows(v, 3)))
collected = collect(windows(v, 3))
println("collected: ", collected)

# k > length(v) → zero windows
println("k > length: ", length(windows(v, 10)))

# k ≤ 0 → error
try
    windows(v, 0)
catch e
    println("error: ", e)
end

# Works with OffsetArray
oa = OffsetArray([10, 20, 30, 40], -1)
for w in windows(oa, 2)
    println("offset window: ", w, " (indices ", firstindex(w), ":", lastindex(w), ")")
end

# Large-scale: sum of all 16-element windows over 10^7 elements
n = 10_000_000
big_v = ones(n)
t0 = time()
result = sum(sum, windows(big_v, 16))
elapsed = time() - t0
println("sum of all 16-windows over 10^7 elements: $result")
println("elapsed: $elapsed s")
