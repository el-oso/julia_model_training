using LinearAlgebra

"""
Fast, cache-blocked matrix multiplication for dense matrices.

No BLAS calls.  Column-major blocked loops with @inbounds @simd on the
innermost loop.  Block sizes tuned for L1 cache (~32 KB on modern CPUs).
"""
function mymul!(C, A, B)
    m, n = size(C)
    p, q = size(B)
    @assert size(A, 1) == m && size(A, 2) == p && n == q "Dimension mismatch"

    fill!(C, 0)

    # Block sizes: 64 blocks the common dimension k and the i dimension
    # so each k-block × i-block tile fits comfortably in L1 cache.
    Bk = 64
    Bi = 64

    # Outer: block the j dimension (columns of C)
    for j1 = 1:Bk:n
        j2 = min(j1 + Bk - 1, n)
        # Middle: block the k dimension (common dimension)
        for k1 = 1:Bk:p
            k2 = min(k1 + Bk - 1, p)
            # Inner: block the i dimension (rows of C)
            for i1 = 1:Bi:m
                i2 = min(i1 + Bi - 1, m)
                for i = i1:i2
                    for k = k1:k2
                        # Innermost: unrolled rank-1 update over the j block.
                        # B[k, j] is strided but j1:j2 fits in L1 cache.
                        @inbounds @simd for j = j1:j2
                            C[i, j] += A[i, k] * B[k, j]
                        end
                    end
                end
            end
        end
    end
    return C
end

# ── correctness check ──────────────────────────────────────────────────────────
function test_correctness()
    println("=" ^ 60)
    println("CORRECTNESS CHECKS")
    println("=" ^ 60)

    for (name, T) in [("Int", Int), ("Float64", Float64), ("Complex{Float32}", Complex{Float32})]
        if T == Int
            A = rem.(rand(Int, 5, 7), 10)
            B = rem.(rand(Int, 7, 4), 10)
        else
            A = rand(T, 5, 7)
            B = rand(T, 7, 4)
        end
        C_ref = A * B  # exact with promoted type
        C = zero(C_ref)
        mymul!(C, A, B)
        ok = C ≈ C_ref
        println("  $(rpad(name, 20))  max |err| = $(maximum(abs, C - C_ref)): $(ok ? "✓" : "✗")")
    end
    println()
end

# ── benchmark against Base.mul! ────────────────────────────────────────────────
function benchmark(n)
    println("=" ^ 60)
    println("BENCHMARK  n = $(n)  (Float64)")
    println("=" ^ 60)

    A = rand(Float64, n, n)
    B = rand(Float64, n, n)

    # Warm up
    mul!(zeros(n, n), A, B)
    mymul!(zeros(n, n), A, B)

    # Base.mul!
    C_ref = similar(A)
    t_mul = @elapsed for _ in 1:5
        mul!(C_ref, A, B)
    end
    # 2·n³ FLOPs per call; 5 calls in @elapsed
    flops_per_call = 2 * n^3
    println("  Base.mul!     $(t_mul / 5 * 1000) ms  $(flops_per_call / (t_mul / 5 * 1e9)) GFLOP/s")

    # mymul!
    C_test = similar(A)
    t_mymul = @elapsed for _ in 1:5
        mymul!(C_test, A, B)
    end
    println("  mymul!        $(t_mymul / 5 * 1000) ms  $(flops_per_call / (t_mymul / 5 * 1e9)) GFLOP/s")

    ratio = t_mul / t_mymul
    println("  ratio (mul!/mymul!) = $(round(ratio, sigdigits=3))")
    println("  C_test ≈ C_ref : $(C_test ≈ C_ref)")
    println()
end

# ── run ────────────────────────────────────────────────────────────────────────
test_correctness()
benchmark(512)
