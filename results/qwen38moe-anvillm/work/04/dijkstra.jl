"""
Dijkstra's algorithm with a hand-rolled binary min-heap (priority queue of
(Float64, Int) pairs).  Returns (dist, prev) and path(prev, target).

  adj[u] = Vector{Tuple{Int, W}} of (neighbor, weight) pairs, W<:Real.
  Unreachable nodes get Inf and prev == 0.
"""

# ── Min-heap (priority queue) ──────────────────────────────────────────────────

mutable struct MinPQ
    heap::Vector{Tuple{Float64, Int}}   # 1-based, min at 1
    sz::Int
end
MinPQ(n::Int) = MinPQ(Vector{Tuple{Float64, Int}}(undef, n), 0)

function Base.push!(pq::MinPQ, v::Tuple{Float64, Int})
    pq.sz += 1; i = pq.sz
    while i > 1
        p = i >> 1
        if pq.heap[p] > v
            pq.heap[i] = pq.heap[p]
            i = p
        else
            break
        end
    end
    pq.heap[i] = v
    pq
end

function Base.pop!(pq::MinPQ)::Tuple{Float64, Int}
    top = pq.heap[1]
    v = pq.heap[pq.sz]     # grab the element being removed FIRST
    pq.sz -= 1
    i = 1
    while (c = i << 1) <= pq.sz
        if c < pq.sz && pq.heap[c+1] < pq.heap[c]
            c += 1
        end
        if pq.heap[c] >= v
            break
        end
        pq.heap[i] = pq.heap[c]
        i = c
    end
    pq.heap[i] = v
    top
end

# ── Dijkstra ───────────────────────────────────────────────────────────────────

function dijkstra(adj::Vector{<:Vector{<:Tuple{Integer, <:Real}}}, src::Integer)
    n = length(adj)
    dist  = fill(Inf, n)
    prev  = fill(0, n)
    dist[src] = 0.0

    pq = MinPQ(n)
    push!(pq, (0.0, src))

    while pq.sz > 0
        d, u = pop!(pq)
        d > dist[u] && continue            # stale entry, skip
        for (v, w) in adj[u]
            d_new = d + float(w)
            if d_new < dist[v]
                dist[v]  = d_new
                prev[v]  = u
                push!(pq, (d_new, v))
            end
        end
    end

    dist, prev
end

# ── Path reconstruction ────────────────────────────────────────────────────────

function path(prev::Vector{Int}, target::Integer)
    target == 0 && return Int[]
    seg = Vector{Int}(undef, 0)
    push!(seg, target)
    while (p = prev[target]) != 0
        target = p
        push!(seg, target)
    end
    reverse!(seg)
end

# ── Tests ───────────────────────────────────────────────────────────────────────

function test()
    adj = [
        [(2, 7),  (3, 9),  (6, 14)],
        [(1, 7),  (3, 10), (4, 15)],
        [(1, 9),  (2, 10), (4, 11), (6, 2)],
        [(2, 15), (3, 11), (5, 6)],
        [(4, 6),  (6, 9)],
        [(1, 14), (3, 2),  (5, 9)],
    ]
    src = 1
    dist, prev = dijkstra(adj, src)
    println("dist = $dist")
    println("prev = $prev")
    @assert dist == [0.0, 7.0, 9.0, 20.0, 20.0, 11.0]
    @assert prev  == [0, 1, 1, 3, 6, 3]
    @assert path(prev, 6) == [1, 3, 6]
    @assert path(prev, 0) == Int[]
    @assert path(prev, 4) == [1, 3, 4]
    println("✓ all sanity checks passed")
end

# ── Benchmark ───────────────────────────────────────────────────────────────────

using Random

function rand_graph(n::Integer, m::Integer)
    rng = MersenneTwister(123)
    adj = [Vector{Tuple{Int, Float64}}(undef, 0) for _ in 1:n]
    for _ in 1:m
        u = rand(rng, 1:n)
        push!(adj[u], (rand(rng, 1:n), rand(rng) * 1000.0))
    end
    adj
end

if abspath(PROGRAM_FILE) == @__FILE__
    test()

    println("\n┌─ Building graph: 10⁶ nodes, 5×10⁶ edges ─────────────────┐")
    @time adj = rand_graph(1_000_000, 5_000_000)

    println("\n┌─ Running Dijkstra (src=1) ────────────────────────────────┐")
    @time dist, prev = dijkstra(adj, 1)

    u_count = count(isinf, dist)
    println("  Unreachable : $u_count")
    println("  Max dist    : $(maximum(filter(x -> x != Inf, dist)))")

    reachable = findall(x -> x != Inf, dist)
    if !isempty(reachable)
        println("  Sample path to node $(reachable[end]): ", path(prev, reachable[end]))
    end
end
