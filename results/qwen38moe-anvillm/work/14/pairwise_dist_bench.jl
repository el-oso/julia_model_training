using BenchmarkTools
using LinearAlgebra

# ─── ORIGINAL ───────────────────────────────────────────────────────────────────
function pairwise_dist_orig(X)
    n = size(X, 1)
    D = zeros(n, n)
    for i in 1:n, j in 1:n
        D[i, j] = sqrt(sum((X[i, :] .- X[j, :]).^2))
    end
    D
end

# ─── OPTIMIZED ─────────────────────────────────────────────────────────────────
function pairwise_dist(X)
    # ||x_i - x_j||² = ||x_i||² + ||x_j||² - 2·x_i·x_j
    # 1. Gram matrix via BLAS gemm (the real bottleneck — highly tuned)
    G = X * X'
    # 2. Diagonal (squared norms)
    d = diag(G)
    # 3. Squared distances: d[i] + d[j] - 2*G[i,j]  (broadcasted)
    D = d .+ d' .- 2 * G
    # 4. Clamp tiny negatives from floating-point before sqrt
    D = ifelse.(D .< 0, 0.0, D)
    sqrt.(D)
end

# ─── BENCHMARK ─────────────────────────────────────────────────────────────────
X = randn(2000, 3)

println("=== Warm-up ===")
_ = pairwise_dist_orig(X)   # compile
_ = pairwise_dist(X)         # compile

println("\n=== Original ===")
@btime pairwise_dist_orig($X)

println("\n=== Optimized ===")
@btime pairwise_dist($X)

# ─── CORRECTNESS CHECK ─────────────────────────────────────────────────────────
D1 = pairwise_dist_orig(X)
D2 = pairwise_dist(X)
println("\n=== Correctness ===")
println("max |D1 - D2| = $(maximum(abs, D1 - D2))")
println("allclose(D1, D2) = $(isapprox(D1, D2, atol=1e-10))")
