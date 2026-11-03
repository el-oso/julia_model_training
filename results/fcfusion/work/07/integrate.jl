"""
    integrate(f, a, b; rtol=1e-8, maxdepth=50)

Adaptive Simpson's rule with Richardson correction.

Returns `(value, errest)` where `errest` is the estimated absolute error.
Generic over numeric types (Float32, Float64, BigFloat).
"""
function integrate(f, a, b; rtol=1e-8, maxdepth=50)
    T = promote_type(typeof(a), typeof(b))
    rtol = T(rtol)

    if a > b
        result, err = integrate(f, b, a; rtol=rtol, maxdepth=maxdepth)
        return (-result, err)
    end

    fa = f(a)
    fb = f(b)
    fm = f((a + b) / 2)

    total_err = Ref(T(0))
    result = _adaptive(f, a, b, fa, fm, fb, 0, rtol, maxdepth, total_err)

    return (result, total_err[])
end

function _adaptive(f, a, b, fa, fm, fb, depth, rtol, maxdepth, total_err)
    h = (b - a)

    # Simpson's rule on [a,b]
    S = (h / 6) * (fa + 4fm + fb)

    # Subdivide and compute Simpson's on halves
    am = (a + b) / 2
    bm = (a + b) / 2
    fam = f(am)
    fmb = f(bm)

    S_left = (h / 12) * (fa + 4fam + fm)
    S_right = (h / 12) * (fm + 4fmb + fb)
    S2 = S_left + S_right

    # Richardson correction: Simpson has O(h⁴) error, correction gives O(h⁶)
    err = (S2 - S) / 15
    R = S2 + err  # Richardson-corrected result

    if abs(err) <= rtol * (abs(R) + 1e-100) || depth >= maxdepth
        if depth >= maxdepth
            println("Warning: maxdepth reached at interval [", a, ", ", b, "]")
        end
        total_err[] += err
        return R
    end

    # Recurse
    left = _adaptive(f, a, am, fa, fam, fm, depth + 1, rtol, maxdepth, total_err)
    right = _adaptive(f, am, b, fm, fmb, fb, depth + 1, rtol, maxdepth, total_err)
    return left + right
end

# Test cases
println("Testing adaptive Simpson's rule with Richardson correction")
println("=" ^ 60)

# Test 1: sin on [0, π], exact = 2
result, err = integrate(sin, 0.0, pi)
println("∫₀^π sin(x) dx = $result")
println("  exact: 2.0, error: $(abs(result - 2.0))")
println("  error estimate: $err")
println()

# Test 2: sqrt on [0, 1], exact = 2/3
# Note: sqrt has infinite derivative at 0, so convergence is slower
result, err = integrate(sqrt, 0.0, 1.0)
println("∫₀¹ sqrt(x) dx = $result")
println("  exact: 0.6666666666666666, error: $(abs(result - 2/3))")
println("  error estimate: $err")
println()

# Test 3: exp(-x²) on [-5, 5], exact = √π * erf(5)
# erf(5) = 1 - 1.5374e-12, so exact ≈ √π to 12 digits
exact_erf5 = 0.9999999999994649  # erf(5) to 16 digits
exact_gauss = sqrt(pi) * exact_erf5
result, err = integrate(x -> exp(-x^2), -5.0, 5.0)
println("∫₋₅⁵ exp(-x²) dx = $result")
println("  exact: $exact_gauss, error: $(abs(result - exact_gauss))")
println("  error estimate: $err")
println()

# Test 4: a > b case
result, err = integrate(sin, pi, 0.0)
println("∫_π^0 sin(x) dx (reversed) = $result")
println("  expected: -2.0, error: $(abs(result + 2.0))")
println()

# Test 5: Float32
result32, err32 = integrate(sin, 0.0f0, Float32(pi))
println("Float32 test: ∫₀^π sin(x) dx = $result32")
println("  exact: 2.0f0, error: $(abs(result32 - 2.0f0))")
println()

# Test 6: BigFloat
setprecision(BigFloat, 50)
pi_big = big(pi)
result_big, err_big = integrate(sin, big(0), pi_big)
println("BigFloat test: ∫₀^π sin(x) dx = $result_big")
println("  exact: 2.0")
println("  error estimate: $err_big")
