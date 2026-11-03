# Debug: print generated expression
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

    funcname = fname.args[1]
    arg_exprs = fname.args[2:end]

    # Build cache type (simplified: always Dict{Any, Any} for now)
    cache_type = Expr(:curly, :Dict, :Any, :Any)

    # Build the wrapped function
    let wrapped = quote
        let cache = $(cache_type)()
            function $(funcname)($(arg_exprs...))
                local key = $(arg_exprs...)
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

    # Print for debugging
    println("=== Generated expression ===")
    show(wrapped)
    println("=== End ===")

    return wrapped
end

const fib = @memoize function fib(n::Int)::Int
    if n <= 1
        return n
    end
    return fib(n - 1) + fib(n - 2)
end

println("fib(10) = $(fib(10))")