module Windows

using OffsetArrays

export windows

"""
    windows(v, k)

Yields each length-`k` contiguous window of `v` as a zero-copy view.

- `k > length(v)` → no windows
- `k ≤ 0` → `ArgumentError`
- Works on any `AbstractVector`, including `OffsetArray`

`collect(windows(v, k))` and `length(windows(v, k))` are supported.
`for w in windows(v, k)` never allocates per window.
"""
struct Windows{V<:AbstractVector}
    v::V
    k::Int
end

function windows(v::AbstractVector, k::Integer)
    k > 0 || throw(ArgumentError("k must be positive, got $k"))
    Windows(v, k)
end

# ── iterator protocol ──────────────────────────────────────────────────────────

Base.IteratorSize(::Type{<:Windows}) = Base.HasLength()
Base.IteratorEltype(::Type{<:Windows}) = Base.HasEltype()

# Each element is a SubArray view; this makes `collect` infer the right container
# type (vector of views, not vector of scalars).
Base.eltype(::Type{<:Windows{V}}) where {V} =
    SubArray{eltype(V), 1, V, Tuple{UnitRange{Int64}}, true}

Base.length(w::Windows) = w.k ≤ length(w.v) ? length(w.v) - w.k + 1 : 0

function Base.iterate(w::Windows)
    n = length(w.v)
    w.k > n && return nothing
    (@view w.v[1:w.k]), 0          # state = 0-based start of first window
end

function Base.iterate(w::Windows, i)
    # i = 0-based start index of last yielded window; next = i+1
    i + w.k ≥ length(w.v) && return nothing
    (@view w.v[i+2:i+1+w.k]), i + 1
end

end # module

using .Windows
using OffsetArrays

# ── demos ──────────────────────────────────────────────────────────────────────

println("=== trivial windows(v,2) ===")
v = [10, 20, 30, 40]
for w in windows(v, 2)
    println(collect(w))          # [10,20]  [20,30]  [30,40]
end
println("length: $(length(windows(v,2)))")

println("\n=== k > n → 0 ===")
println(length(windows(v, 5)))   # 0

println("\n=== k≤0 → ArgumentError ===")
try windows(v, 0)  catch e; println("  k=0: ", e)  end
try windows(v, -1) catch e; println("  k=-1: ", e) end

println("\n=== k=1 → identity ===")
s = sum(sum, windows(v, 1))
println("  sum(sum, windows(v,1)) = $s  (expected $(sum(v)))")

println("\n=== OffsetArray ===")
o = OffsetArray([10, 20, 30, 40], 0)
for w in windows(o, 2)
    println(collect(w))
end
println("  length: $(length(windows(o, 2)))")

# ── benchmark: sum(sum, windows(v, 16)) on 10⁷ ───────────────────────────────

using BenchmarkTools

n = 10^7
v = randn(Float64, n)
k = 16

println("\n=== sum(sum, windows(v,$k)) on 10^7 ===")
result = @btime sum(sum, windows(v, $k))
println("  → $result")
println("  verify (exact sum of v): $(sum(v))")

println("\n=== collect shares memory (no copy) ===")
ws = collect(windows(v, 3))
println("  collect length: $(length(ws))")
println("  ws[1] == v[1:3]  ?  $(ws[1] .== view(v, 1:3))")
println("  ws[1].parent === v ? $(ws[1].parent === v)")
