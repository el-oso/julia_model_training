"""
lu_pp.jl — LU with partial pivoting (Doolittle), generic element type.

    lu_pp!(A)      → (L, U, p)   in-place on A
    lu_pp(A)       → (L, U, p)   non-mutating (copies A)
    lu_solve(L,U,p,b) → x   solves A*x = b via LU factors

Property:  A[p, :] ≈ L * U
Throws SingularException(k) if pivot at step k is zero.
"""

using LinearAlgebra

# ────────────────────────────────────────────────────────────────────────
# LU with partial pivoting (in-place on A)
# ────────────────────────────────────────────────────────────────────────

function lu_pp!(A::AbstractMatrix{T}) where T
    m, n = size(A)
    p = collect(1:min(m, n))

    for k = 1:min(m, n)
        # ── partial pivoting: find max |A[i,k]| for i ≥ k ──
        pivot_idx = k
        max_abs = abs(A[k, k])
        for i = k+1:m
            a = abs(A[i, k])
            if a > max_abs
                max_abs = a
                pivot_idx = i
            end
        end

        if max_abs == zero(T)
            throw(SingularException(k))
        end

        # ── swap rows k and pivot_idx in A ──
        if pivot_idx != k
            for j = 1:n
                A[k, j], A[pivot_idx, j] = A[pivot_idx, j], A[k, j]
            end
            p[k], p[pivot_idx] = p[pivot_idx], p[k]
        end

        # ── elimination ──
        for i = k+1:m
            factor = A[i, k] / A[k, k]
            A[i, k] = factor           # store L[i,k]
            for j = k+1:n
                A[i, j] -= factor * A[k, j]
            end
        end
    end

    # ── extract L and U from the factorised matrix ──
    L = similar(A, m, m)
    U = similar(A, m, n)

    for i = 1:m
        for j = 1:m
            if i > j
                L[i, j] = A[i, j]
            elseif i == j
                L[i, j] = one(T)
            else
                L[i, j] = zero(T)
            end
        end
        for j = 1:n
            if i <= j
                U[i, j] = A[i, j]
            else
                U[i, j] = zero(T)
            end
        end
    end

    return L, U, p
end

# ────────────────────────────────────────────────────────────────────────
# Non-mutating wrapper
# ────────────────────────────────────────────────────────────────────────

lu_pp(A::AbstractMatrix) = lu_pp!(copy(A))

# ────────────────────────────────────────────────────────────────────────
# Solve A*x = b given LU factors
# ────────────────────────────────────────────────────────────────────────

function lu_solve(L::AbstractMatrix, U::AbstractMatrix,
                  p::AbstractVector, b::AbstractVector)
    m = size(L, 1)
    pb = b[p]                         # permuted right-hand side

    # Forward substitution:  L * y = pb
    y = similar(b, m)
    for i = 1:m
        s = zero(eltype(b))
        for j = 1:i-1
            s += L[i, j] * y[j]
        end
        y[i] = pb[i] - s
    end

    # Backward substitution:  U * x = y
    x = similar(b, m)
    for i = m:-1:1
        s = zero(eltype(b))
        for j = i+1:m
            s += U[i, j] * x[j]
        end
        x[i] = (y[i] - s) / U[i, i]
    end

    return x
end

# ────────────────────────────────────────────────────────────────────────
# Tests
# ────────────────────────────────────────────────────────────────────────

function test()
    println("=== correctness tests ===")

    # 1.  A[p,:] ≈ L*U
    A = randn(8, 8)
    L, U, p = lu_pp(A)
    err = norm(A[p, :] - L * U)
    println("  L*U ≈ A[p,:]  err = $(err): $(err < 1e-10 ? "PASS" : "FAIL")")

    # 2.  lu_solve round-trip
    b = randn(8)
    x = lu_solve(L, U, p, b)
    err = norm(A * x - b)
    println("  A*x ≈ b       err = $(err): $(err < 1e-10 ? "PASS" : "FAIL")")

    # 3.  Singular detection (exactly zero pivot)
    A_sing = [0.0 0.0; 0.0 0.0]
    ok = false
    try
        lu_pp(A_sing)
    catch e
        ok = e isa SingularException
    end
    println("  SingularException: $(ok ? "PASS" : "FAIL")")

    # 4.  Rational{BigInt} (exact arithmetic)
    A_rat = [Rational{BigInt}(1) Rational{BigInt}(2);
             Rational{BigInt}(3) Rational{BigInt}(4)]
    Lr, Ur, pr = lu_pp(A_rat)
    err = norm(A_rat[pr, :] - Lr * Ur)
    println("  Rational{BigInt} L*U err = $(err): $(err == 0 ? "PASS" : "FAIL")")

    # 5.  lu_pp! mutates its argument
    A2 = randn(5, 5)
    A2_orig = copy(A2)
    lu_pp!(A2)
    println("  lu_pp! mutates: $(A2 != A2_orig ? "PASS" : "FAIL")")

    println("=== all done ===")
end

# ────────────────────────────────────────────────────────────────────────
# Benchmark vs LinearAlgebra.lu  (n = 500)
# ────────────────────────────────────────────────────────────────────────

function benchmark()
    println("\n=== benchmark  n = 500 ===")
    n = 500
    A = randn(n, n)

    # Warm up
    lu_pp!(copy(A))
    lu(A)

    # Time our lu_pp!
    t1 = @elapsed for _ in 1:5
        lu_pp!(copy(A))
    end
    println("  lu_pp! (5 runs): $(t1/5 * 1000) ms")

    # Time LinearAlgebra.lu
    t2 = @elapsed for _ in 1:5
        lu(A)
    end
    println("  LinearAlgebra.lu (5 runs): $(t2/5 * 1000) ms")

    # Speed ratio
    println("  ratio (ours / LA): $(t1/t2)")
end

# ────────────────────────────────────────────────────────────────────────
# Run
# ────────────────────────────────────────────────────────────────────────

test()
benchmark()
