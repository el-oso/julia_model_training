# Test: macro that generates a let block with a function
macro make_fib()
    let wrapped = quote
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
    return wrapped
end

const fib = @make_fib
println("fib(10) = $(fib(10))")