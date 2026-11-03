# Test: generate function with user-provided body

macro make_fib_user_body(body)
    return quote
        let cache = Dict{Any, Any}()
            function fib(n::Int)
                if haskey(cache, n)
                    return cache[n]
                end
                local result = $(body)
                cache[n] = result
                return result
            end
            fib
        end
    end
end

const fib = @make_fib_user_body begin
    if n <= 1
        n
    else
        fib(n - 1) + fib(n - 2)
    end
end

println("fib(10) = $(fib(10))")