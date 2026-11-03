import LinearAlgebra: lu, SingularException, I, norm
using BenchmarkTools

# LU decomposition with partial pivoting (in-place)
# Returns (L, U, p) where A[p, :] = L * U
function lu_pp!(A)
    n = size(A, 1)
    @assert size(A, 1) == size(A, 2) "Matrix must be square"

    p = collect(1:n)

    for k in 1:n
        # Partial pivoting: find max element in column k below diagonal
        pivot_row = k
        max_val = abs(A[k, k])
        for i in k+1:n
            val = abs(A[i, k])
            if val > max_val
                max_val = val
                pivot_row = i
            end
        end

        # Swap rows in A
        if pivot_row != k
            A[k, :], A[pivot_row, :] = A[pivot_row, :], A[k, :]
            # Swap in permutation
            p[k], p[pivot_row] = p[pivot_row], p[k]
        end

        # Check for singularity
        if A[k, k] == 0
            throw(SingularException(k))
        end

        # Scale column k below diagonal (store multipliers in L position)
        inv_pivot = inv(A[k, k])
        for i in k+1:n
            A[i, k] *= inv_pivot
        end

        # Eliminate: update trailing submatrix
        # Column-major friendly: inner loop over rows (i)
        for j in k+1:n
            Akj = A[k, j]
            for i in k+1:n
                A[i, j] -= A[i, k] * Akj
            end
        end
    end

    # Extract L (unit lower triangular)
    L = Matrix{eltype(A)}(I, n, n)
    for i in 2:n
        for j in 1:i-1
            L[i, j] = A[i, j]
        end
    end

    # Extract U (upper triangular)
    U = zero(A)
    for i in 1:n
        for j in i:n
            U[i, j] = A[i, j]
        end
    end

    return L, U, p
end

# Out-of-place version
function lu_pp(A)
    B = copy(A)
    return lu_pp!(B)
end

# Solve Ax = b given LU factorization with partial pivoting
function lu_solve(L, U, p, b)
    n = length(b)

    # Apply permutation to RHS
    pb = b[p]

    # Forward substitution: L y = pb (L has unit diagonal)
    y = zero(pb)
    for i in 1:n
        y[i] = pb[i]
        for j in 1:i-1
            y[i] -= L[i, j] * y[j]
        end
    end

    # Backward substitution: U x = y
    x = zero(y)
    for i in n:-1:1
        x[i] = y[i]
        for j in i+1:n
            x[i] -= U[i, j] * x[j]
        end
        x[i] /= U[i, i]
    end

    return x
end

function print_matrix(M)
    for i in 1:size(M, 1)
        row = map(x -> string(x), M[i, :])
        println(join(row, " "))
    end
end

# ============ Testing ============

println("=== Correctness tests ===")

# Float64 test
n = 50
A = rand(n, n)
b = rand(n)

L, U, p = lu_pp(A)
residual = norm(A[p, :] - L * U) / norm(A)
println("Float64 decomposition residual: $residual")

x = lu_solve(L, U, p, b)
solve_res = norm(A * x - b) / norm(b)
println("Float64 solve residual: $solve_res")

# Compare with LinearAlgebra
fl = lu(A)
x_la = fl \ b
println("Solution difference vs LinearAlgebra: ", norm(x - x_la) / norm(x_la))

# Singular matrix test
try
    Asing = zeros(3, 3)
    Asing[1, 1] = 1.0
    lu_pp!(Asing)
    println("ERROR: Should have thrown SingularException")
catch e
    println("Singular matrix correctly throws: $e")
end

# Exact arithmetic with Rational{BigInt}
println("\n=== Exact arithmetic (Rational{BigInt}) test ===")
Ar = [2 1 3; 4 3 7; 6 5 9]
Ar = Ar .|> (x -> Rational(BigInt(x), 1))

Lr, Ur, pr = lu_pp(Ar)
println("Exact decomposition:")
println("L:")
print_matrix(Lr)
println("U:")
print_matrix(Ur)
println("p: $pr")

# Verify A[p, :] = L * U exactly
reconstructed = Lr * Ur
println("A[p, :] == L*U: ", Ar[pr, :] == reconstructed)

# Solve with exact arithmetic
br = [1; 2; 3]
br = br .|> (x -> Rational(BigInt(x), 1))
xr = lu_solve(Lr, Ur, pr, br)
println("Exact solution: ", xr')
println("Verification A*x == b: ", Ar * xr == br)

# ============ Benchmarking ============

println("\n=== Benchmarking at n=500 ===")

n = 500
A = rand(n, n)

println("Our lu_pp:")
t1 = @belapsed lu_pp($A)
println("  $(t1 * 1000) ms")

println("LinearAlgebra.lu:")
t2 = @belapsed lu($A)
println("  $(t2 * 1000) ms")

println("Speedup: $(t1/t2)x (higher is slower)")

# Verify our result matches
L, U, p = lu_pp(A)
fl = lu(A)
println("Factorization difference: ", norm(L*U - fl.L*fl.U) / norm(A))
