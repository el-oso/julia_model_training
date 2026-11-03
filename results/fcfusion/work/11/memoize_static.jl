# Memoization macro using Julia 1.10+ static variables
# This defines the function at the top level with a persistent cache.

macro memoize(expr)
    # Parse function definition
    if expr.head == :function
        fname = expr.args[1]
        body = expr.args[2]
    elseif expr.head == :(=)
        fname = expr.args[1]
        body = expr.args[2]
    else
        error("@memoize expects a function definition")
    end

    # fname is Expr(:call, :fib, :(n::Int))
    funcname = fname.args[1]
    arg_exprs = fname.args[2:end]

    # Extract argument names for the cache key
    arg_names = []
    for arg in arg_exprs
        if arg.head == :(::)
            push!(arg_names, arg.args[1])
        else
            push!(arg_names, arg)
        end
    end

    # Build cache key expression
    if length(arg_names) == 1
        key_expr = arg_names[1]
    else
        key_expr = Expr(:tuple, arg_names...)
    end

    # Generate function with static cache
    let wrapped = quote
        function $(funcname)($(arg_exprs...))
            static cache = Dict{Any, Any}()
            local key = $(key_expr)
            if haskey(cache, key)
                return cache[key]
            end
            local result = $(body)
            cache[key] = result
            return result
        end
    end

    return wrapped
end

# Demo: Fibonacci
@memoize function fib(n::Int)::Int
    if n <= 1
        return n
    end
    return fib(n - 1) + fib(n - 2)
end

println("fib(90) = $(fib(90))")
println("fib(90) again (cached) = $(fib(90))")