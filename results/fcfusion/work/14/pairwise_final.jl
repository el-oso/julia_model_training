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
    norms = [dot(x, x) for x in eachrow(X)]
    G = X * X'
    D2 = norms .+ norms' .- 2*G
    D2 = max.(D2, 0.0)
    return sqrt.(D2)
end

X = rand(2000, 3)

# Verify correctness
D_orig = pairwise_dist_original(X)
D_opt = pairwise_dist_optimized(X)
println("Max diff: ", maximum(abs.(D_opt .- D_orig)))

# Benchmark
println("\n=== Original ===")
t1 = @benchmark pairwise_dist_original($X)
println("Median: ", round(minimum(t1).time / 1e6, digits=2), " ms")
println("Allocs: ", minimum(t1).allocs)

println("\n=== Optimized ===")
t2 = @benchmark pairwise_dist_optimized($X)
println("Median: ", round(minimum(t2).time / 1e6, digits=2), " ms")
println("Allocs: ", minimum(t2).allocs)

speedup = minimum(t1).time / minimum(t2).time
println("\nSpeedup: ", round(speedup, digits=1), "x")
