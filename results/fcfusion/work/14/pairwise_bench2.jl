using BenchmarkTools
using LinearAlgebra

function pairwise_dist_original(X)
    n = size(X, 1)
    D = zeros(n, n)
    for i in 1:n
        for j in 1:n
            D[i, j] = sqrt(sum((X[i, :] .- X[j, :]).^2))
        end
    end
    return D
end

function pairwise_dist_optimized(X)
    n = size(X, 1)
    norms = sum(x -> dot(x, x), eachrow(X))
    G = X * X'
    @. G = norms + norms' - 2*G
    @. G = max(G, 0.0)
    @. G = sqrt(G)
    return G
end

X = rand(2000, 3)

# Verify correctness
D_orig = pairwise_dist_original(X)
D_opt = pairwise_dist_optimized(X)
println("Max diff: ", maximum(abs.(D_opt .- D_orig)))

# Benchmark with fewer trials to reduce output
println("\n=== Original ===")
t1 = @benchmark pairwise_dist_original($X)
println("Median: ", minimum(t1).time, " ns (", round(minimum(t1).time / 1e6, digits=2), " ms)")
println("Allocs: ", minimum(t1).allocs, " (", round(minimum(t1).alloc_bytes / 1e6, digits=2), " MB)")

println("\n=== Optimized ===")
t2 = @benchmark pairwise_dist_optimized($X)
println("Median: ", minimum(t2).time, " ns (", round(minimum(t2).time / 1e6, digits=2), " ms)")
println("Allocs: ", minimum(t2).allocs, " (", round(minimum(t2).alloc_bytes / 1e6, digits=2), " MB)")

speedup = minimum(t1).time / minimum(t2).time
println("\nSpeedup: ", round(speedup, digits=1), "x")
println("Alloc reduction: ", round(minimum(t1).alloc_bytes / minimum(t2).alloc_bytes, digits=1), "x")
