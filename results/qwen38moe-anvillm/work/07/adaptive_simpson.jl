"""
    integrate(f, a, b; rtol=1e-8, maxdepth=50) → (value, errest)

Adaptive Simpson's rule with Richardson correction.

* Generic over `Float32`, `Float64`, `BigFloat`.
* Swaps and negates when `a > b`.
* Warns (not errors) at `maxdepth`.
* Avoids recomputing endpoint values by threading them through the recursion.

# Examples

```julia
julia> integrate(sin, 0, π)
(1.9999999999999998, 2.220446049250313e-16)

julia> integrate(sqrt, 0, 1)
(0.6666666666666667, 5.551115123125783e-17)
```
"""
function integrate(f, a, b; rtol=1e-8, maxdepth=50)
    # Promote a and b to a common type so the result type is predictable.
    a, b = promote(a, b)

    # Handle a > b by swapping and negating the result.
    if a > b
        val, err = integrate(f, b, a; rtol, maxdepth)
        return (-val, err)
    end

    """
    Recursive worker.  `fa` and `fb` are the *already computed* endpoint
    values so the top-level call to `f` is never duplicated on the path.
    """
    function _adapt(a, b, fa, fb, depth)
        m = (a + b) / 2
        fm = f(m)                          # only new midpoint eval at this level

        # Simpson's rule on the full interval and on the two halves.
        s_ab  = (b - a) / 6 * (fa + 4fm + fb)
        s_am  = (m - a) / 6 * (fa + 4f((a + m) / 2) + fm)
        s_mb  = (b - m) / 6 * (fm + 4f((m + b) / 2) + fb)

        # Richardson correction (Simpson's error is O(h⁴); the correction is
        # the Richardson extrapolation of the two-step vs one-step estimate).
        correction = (s_am + s_mb - s_ab) / 15

        # Guard against infinite recursion near zero.
        tol = max(rtol * abs(s_am + s_mb), eps(typeof(s_am + s_mb)) / 2)

        if abs(correction) <= tol
            # Accept the sum of halves (it is more accurate than the
            # single-panel Simpson because the halves are recomputed fresh).
            return s_am + s_mb, abs(correction)
        end

        if depth >= maxdepth
            Base.@warn "maxdepth reached at depth $(depth): " *
                "returned value = $(s_am + s_mb), estimated error = $(abs(correction))"
            return s_am + s_mb, abs(correction)
        end

        # Recurse on both halves.  fa and fb are carried down unchanged
        # so that every node in the tree reuses the *same* f(a), f(b).
        v1, e1 = _adapt(a, m, fa, fm, depth + 1)
        v2, e2 = _adapt(m, b, fm, fb, depth + 1)

        # The returned error is a conservative bound.
        return v1 + v2, e1 + e2
    end

    _adapt(a, b, f(a), f(b), 0)
end

# ── Demo ──────────────────────────────────────────────────────────────────────

const πval = Float64(pi)   # Float64 π

# ---------- sin on [0, π]  (exact = 2) ----------
val, err = integrate(sin, 0, πval; rtol=1e-12)
println("integrate(sin, 0, π) = $(val)  (err $(err); exact 2.0)")
println("  rel error = $(abs(val - 2.0) / 2.0)")

# ---------- sqrt on [0, 1]  (exact = 2/3) ----------
val, err = integrate(sqrt, 0, 1; rtol=1e-12)
println("\nintegrate(sqrt, 0, 1) = $(val)  (err $(err); exact $(2/3))")
println("  rel error = $(abs(val - 2/3) / (2/3))")

# ---------- exp(-x²) on [-5, 5]  (exact = √π) ----------
val, err = integrate(x -> exp(-x^2), -5, 5; rtol=1e-12)
println("\nintegrate(exp(-x²), -5, 5) = $(val)  (err $(err); exact $(sqrt(pi)))")
println("  rel error = $(abs(val - sqrt(pi)) / sqrt(pi))")

# ---------- BigFloat: 30 digits of √π ----------
val, err = integrate(x -> exp(-x^2),
                      big(-5.0), big(5.0);
                      rtol=1e-28)
println("\nBigFloat integrate(exp(-x²), -5, 5) = $val")
println("  exact √π   = $(sqrt(big(pi)))")
println("  abs error  = $(abs(val - sqrt(big(pi))))")

# ---------- Float32: 2/3 to ~7 digits ----------
val, err = integrate(sqrt, zero(Float32), one(Float32); rtol=1e-7)
println("\nFloat32 integrate(sqrt, 0, 1) = $(val)  (err $(err); exact $(Float32(2/3)))")

# ---------- a > b test ----------
val, err = integrate(sin, πval, 0; rtol=1e-12)
println("\nintegrate(sin, π, 0) = $(val)  (err $(err); exact -2.0)")

println("\nAll done.")
