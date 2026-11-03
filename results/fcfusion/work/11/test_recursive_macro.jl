# Test: macro that generates a recursive function with cache

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
            fib
        end
    end
end

const fib = @make_fib
println("fib(10) = $(fib(10))")