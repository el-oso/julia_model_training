# Test: manually written memoized fib to verify the pattern works

let cache = Dict{Int, Any}()
    function fib(n::Int)
        if haskey(cache, n)
            return cache[n]
        end
        if n <= 1
            result = n
        else
            result = fib(n - 1) + fib(n - 2)
        end
        cache[n] = result
        return result
    end
    println("fib(90) = $(fib(90))")
end