# Memoization macro that generates a let block with closure

macro memoize(expr)
    # Parse the function definition
    if expr.head == :function
        fname = expr.args[1]
        body = expr.args[2]
    elseif expr.head == :(=)
        fname = expr.args[1]
        body = expr.args[2]
    else
        error("@memoize expects a function definition")
    end

    # fname is Expr(:call, :fib, :(n::Int), :Int)
    # We need to extract the function name and arguments
    funcname = fname.args[1]
    arg_exprs = fname.args[2:end]

    # Build the key expression (tuple of arguments)
    if length(arg_exprs) == 1
        key_expr = arg_exprs[1]
    else
        key_expr = Expr(:tuple, arg_exprs...)
    end

    # Generate a closure that wraps the function with a cache
    let wrapped = quote
        let cache = Dict{Any, Any}()
            function $(funcname)($(arg_exprs...))
                local key = $(key_expr)
                if haskey(cache, key)
                    return cache[key]
                end
                local result = $(body)
                cache[key] = result
                return result
            end
            $(funcname)
        end
    end

    return wrapped
end

# Demo: Fibonacci
# The macro generates a let block, so the user must assign the result.
const fib = @memoize function fib(n::Int)::Int
    if n <= 1
        return n
    end
    return fib(n - 1) + fib(n - 2)
end

println("fib(90) = $(fib(90))")
println("fib(90) again (cached) = $(fib(90))")