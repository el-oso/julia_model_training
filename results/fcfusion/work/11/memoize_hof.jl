# Memoization using a higher-order function
# This is simpler and more reliable than a macro.

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

# Demo: Fibonacci
function fib(n::Int)::Int
    if n <= 1
        return n
    end
    return fib(n - 1) + fib(n - 2)
end

fib_memo = memoize(fib)
println("fib(90) = $(fib_memo(90))")
println("fib(90) again (cached) = $(fib_memo(90))")