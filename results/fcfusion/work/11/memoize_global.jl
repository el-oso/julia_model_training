# Memoization with global cache (no let block)

const memoize_cache_fib = Dict{Any, Any}()

function fib(n::Int)::Int
    local key = n
    if haskey(memoize_cache_fib, key)
        return memoize_cache_fib[key]
    end
    local result
    if n <= 1
        result = n
    else
        result = fib(n - 1) + fib(n - 2)
    end
    memoize_cache_fib[key] = result
    return result
end

println("fib(90) = $(fib(90))")
println("fib(90) again (cached) = $(fib(90))")