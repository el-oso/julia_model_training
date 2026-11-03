"""
Cache-blocked matrix multiplication for dense matrices of any numeric type.
Loop order: i (row of C), j (col of C), k (contract), with 128x128 blocks.
No BLAS calls.
"""
function mymul!(C, A, B)
    m, n = size(C)
    pa, qa = size(A)
    pb, qb = size(B)
    if pa != m || qa != pb || qb != n
        throw(DimensionMismatch("incompatible dimensions: C($m,$n), A($pa,$qa), B($pb,$qb)"))
    end

    fill!(C, zero(eltype(C)))

    # Block size tuned for L1/L2 cache; 128 works well for most types
    BLOCK = 128

    # Blocked triple loop in column-major order
    for i0 in 1:BLOCK:m
        i1 = min(i0 + BLOCK - 1, m)
        for j0 in 1:BLOCK:n
            j1 = min(j0 + BLOCK - 1, n)
            for k0 in 1:BLOCK:qa
                k1 = min(k0 + BLOCK - 1, qa)
                # Inner block: compute C[i0:i1, j0:j1] += A[i0:i1, k0:k1] * B[k0:k1, j0:j1]
                for j = j0:j1
                    for i = i0:i1
                        s = zero(eltype(C))
                        for k = k0:k1
                            s += A[i, k] * B[k, j]
                        end
                        C[i, j] += s
                    end
                end
            end
        end
    end
    return C
end

# Verify correctness on small matrices
using LinearAlgebra

function verify()
    for T in [Float64, Int, Complex{Float32}]
        a = rand(T, 4, 5)
        b = rand(T, 5, 3)
        c = similar(a[:, 1:3], T)
        d = copy(c)
        fill!(c, zero(T))
        fill!(d, zero(T))
        mymul!(c, a, b)
        mul!(d, a, b, 1.0, 0.0)
        if T <: Integer
            if c != d
                println("MISMATCH for $T")
                return false
            end
        else
            tol = 100 * eps(real(T))
            if norm(c - d) > tol * norm(d)
                println("MISMATCH for $T")
                return false
            end
        end
        println("$T: correct")
    end
    return true
end

verify()

# Benchmark at n=512 for Float64
using BenchmarkTools

n = 512
a = rand(Float64, n, n)
b = rand(Float64, n, n)
c = similar(a)
d = similar(a)

@time mymul!(c, a, b)
fill!(d, 0.0)
@time mul!(d, a, b, 1.0, 0.0)

println("difference: ", norm(c - d))

# Demo on Int
ia = rand(1:10, 3, 4)
ib = rand(1:10, 4, 3)
ic = zeros(Int, 3, 3)
mymul!(ic, ia, ib)
println("\nInt demo:")
println(ia * ib)
println(ic)

# Demo on Complex{Float32}
ca = rand(Complex{Float32}, 3, 3)
cb = rand(Complex{Float32}, 3, 3)
cc = zeros(Complex{Float32}, 3, 3)
mymul!(cc, ca, cb)
println("\nComplex{Float32} demo:")
println(ca * cb)
println(cc)
