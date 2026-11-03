using Random
include("dijkstra.jl")

# Test correctness on a small graph
adj_small = [
    [(2, 4), (3, 1)],
    [(4, 1)],
    [(2, 2), (4, 5)],
    []
]
dist, prev = dijkstra(adj_small, 1)
println("Small graph distances: ", dist)
println("Path 1->4: ", path(prev, 4))

# Benchmark on large random graph
Random.seed!(42)
n = 1_000_000
m = 5_000_000

println("Building graph with $n nodes, $m edges...")
adj = Vector{Vector{Tuple{Int,Float64}}}(undef, n + 1)
for i in 1:(n+1)
    adj[i] = Vector{Tuple{Int,Float64}}()
end

for _ in 1:m
    u = rand(1:n)
    v = rand(1:n)
    w = rand() * 10.0
    push!(adj[u], (v, w))
end

src = 1
println("Running Dijkstra...")
@time begin
    dist, prev = dijkstra(adj, src)
end

reachable = count(d -> d < Inf, dist)
println("Reachable nodes: $reachable")
println("Done.")
