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

# Optimized: use ||x-y||^2 = ||x||^2 + ||y||^2 - 2(x·y)
# Compute all dot products at once via GEMM
function pairwise_dist_optimized(X)
    n = size(X, 1)
    # Precompute squared norms
    norms = sum(x -> dot(x, x), eachrow(X))
    # Compute dot products via matrix multiplication
    G = X * X'  # Gram matrix
    # D[i,j]^2 = norms[i] + norms[j] - 2*G[i,j]
    D2 = norms .+ norms' .- 2*G
    # Clamp negatives due to floating point
    D2 = max.(D2, 0.0)
    return sqrt.(D2)
end

# Even more optimized: avoid the temp D2 array, do sqrt in-place
function pairwise_dist_optimized_v2(X)
    n = size(X, 1)
    norms = sum(x -> dot(x, x), eachrow(X))
    G = X * X'
    # Reuse G as workspace for D2
    @. G = norms + norms' - 2*G
    @. G = max(G, 0.0)
    @. G = sqrt(G)
    return G
end

# Check results match
X = rand(2000, 3)
D_orig = pairwise_dist_original(X)
D_opt = pairwise_dist_optimized(X)
D_opt2 = pairwise_dist_optimized_v2(X)

println("Max diff opt vs orig: ", maximum(abs.(D_opt .- D_orig)))
println("Max diff opt2 vs orig: ", maximum(abs.(D_opt2 .- D_orig)))

# Benchmark
println("\n=== Original ===")
t1 = @btime pairwise_dist_original($X)
println("Time: ", t1)

println("\n=== Optimized (formula + GEMM) ===")
t2 = @btime pairwise_dist_optimized($X)
println("Time: ", t2)

println("\n=== Optimized v2 (in-place) ===")
t3 = @btime pairwise_dist_optimized_v2($X)
println("Time: ", t3)

println("\nSpeedup opt/original: ", t1 / t2)
println("Speedup opt2/original: ", t1 / t3)
