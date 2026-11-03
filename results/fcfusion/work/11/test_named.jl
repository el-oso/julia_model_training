# Test: macro that generates a named function directly
macro make_fib()
    return quote
        let cache = Dict{Any, Any}()
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
        end
    end
end

@make_fib
println("fib(10) = $(fib(10))")