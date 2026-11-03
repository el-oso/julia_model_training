# Test: macro that generates an anonymous function with closure
macro make_fib()
    let wrapped = quote
        let cache = Dict{Any, Any}()
            function(n::Int)
                if haskey(cache, n)
                    return cache[n]
                end
                if n <= 1
                    result = n
                else
                    result = n - 1 + n - 2
                end
                cache[n] = result
                return result
            end
        end
    end
    return wrapped
end

const fib = @make_fib
println("fib(5) = $(fib(5))")