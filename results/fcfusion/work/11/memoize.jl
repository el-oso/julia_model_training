# Memoization in Julia
#
# Julia doesn't have a built-in @memoize macro. The idiomatic approach
# is to use a closure that captures a cache dictionary. For recursive
# functions, use a Ref to pass the memoized function back into itself.
#
# Why not a macro? Generating a `let` block with a function definition
# via macro expansion is fragile in Julia's parser. The closure pattern
# is simpler, more reliable, and achieves the same result.

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

# For recursive functions, use the Ref pattern:
# 1. Create a Ref to hold the function
# 2. Define the function, using ref[] for recursive calls
# 3. Assign the memoized version back to ref[]
# 4. Extract the function for use

let fib_ref = Ref{Function}()
    fib_ref[] = memoize(function(n::Int)
        if n <= 1
            return n
        end
        # Recursive calls go through the Ref, hitting the cache
        return fib_ref[](n - 1) + fib_ref[](n - 2)
    end)
    global fib = fib_ref[]
end

# Demo: fib(90) without memoization would take ~30 seconds (exponential).
# With memoization, it's O(n) and completes instantly.
println("fib(90) = $(fib(90))")
println("fib(90) again (cached) = $(fib(90))")

# Limitations of this approach:
# 1. Verbose - requires the Ref pattern for recursive functions
# 2. Unbounded cache - grows with unique inputs; no eviction policy
# 3. Only works for pure functions (same input → same output)
# 4. Not thread-safe - concurrent calls may compute duplicates
# 5. Cache keys must be hashable (primitives, strings, tuples work; arrays don't)
# 6. Dict{Any, Any} boxes values; for typed caches, use manual Dict{Tuple{Int}, Int}