# Memoization using Ref for recursive functions

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

# For recursive functions, use a Ref to pass the memoized function back
let fib_ref = Ref{Function}()
    fib_ref[] = memoize(function(n)
        if n <= 1
            return n
        end
        return fib_ref[](n - 1) + fib_ref[](n - 2)
    end)
    global fib = fib_ref[]
end

println("fib(90) = $(fib(90))")
println("fib(90) again (cached) = $(fib(90))")