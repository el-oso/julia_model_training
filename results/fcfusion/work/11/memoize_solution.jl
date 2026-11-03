# Memoization in Julia
#
# Julia doesn't have a built-in @memoize macro, but we can implement
# memoization using closures and Ref for recursive functions.
#
# For non-recursive functions, use memoize(f).
# For recursive functions, use the Ref pattern shown below.

# Generic memoize for non-recursive functions
function memoize(f)
    let cache = Dict{Any, Any}()
        return function(x)
            if haskey(cache, x)
                return cache[x]
            end
            result = f(x)
            cache[x] = result
            return result
        end
    end
end

# For recursive functions, we need to pass the memoized function back
# into itself. We use a Ref to achieve this.
#
# Pattern:
#   let f_ref = Ref{Function}()
#       f_ref[] = memoize(function(x)
#           # base case
#           # recursive case: f_ref[](smaller_x)
#       end)
#       f = f_ref[]
#   end

# Example: Fibonacci with memoization
let fib_ref = Ref{Function}()
    fib_ref[] = memoize(function(n::Int)
        if n <= 1
            return n
        end
        return fib_ref[](n - 1) + fib_ref[](n - 2)
    end)
    global fib = fib_ref[]
end

println("fib(90) = $(fib(90))")
println("fib(90) again (cached) = $(fib(90))")

# Without memoization, fib(90) would take forever (exponential time).
# With memoization, it's O(n) time and O(n) space.

# Limitations:
# 1. The Ref pattern is verbose and not as clean as a @memoize macro.
# 2. The cache is unbounded - it grows with the number of unique inputs.
# 3. Only works for pure functions (same input always gives same output).
# 4. Not thread-safe - concurrent calls may compute the same value twice.
# 5. Cache keys must be hashable (primitives, strings, tuples work; arrays don't).