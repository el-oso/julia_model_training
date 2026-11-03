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
    D2 = norms .+ norms' .- 2*G
    D2 = max.(D2, 0.0)
    return sqrt.(D2)
end

X = rand(2000, 3)

# Debug: check specific entry
n = 10
X_small = rand(n, 3)
D_orig_small = pairwise_dist_original(X_small)
D_opt_small = pairwise_dist_optimized(X_small)
println("Small matrix max diff: ", maximum(abs.(D_opt_small .- D_orig_small)))
println("D_orig[1,2]: ", D_orig_small[1,2])
println("D_opt[1,2]: ", D_opt_small[1,2])

# Manual check
x1 = X_small[1, :]
x2 = X_small[2, :]
manual = sqrt(sum((x1 .- x2).^2))
manual2 = sqrt(dot(x1,x1) + dot(x2,x2) - 2*dot(x1,x2))
println("Manual: ", manual)
println("Manual2: ", manual2)

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
