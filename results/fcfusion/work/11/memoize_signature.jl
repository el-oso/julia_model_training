# Memoization macro preserving original signature

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

    # fname is Expr(:call, :(fib(n::Int)), :Int)
    # fname.args[1] is the function name and arguments
    # fname.args[2] is the return type (if present)
    func_sig = fname.args[1]  # :(fib(n::Int))
    return_type = length(fname.args) > 1 ? fname.args[2] : nothing

    # func_sig is Expr(:call, :fib, :(n::Int))
    funcname = func_sig.args[1]
    arg_exprs = func_sig.args[2:end]

    # Build argument names (without type annotations)
    arg_names = []
    for arg in arg_exprs
        if arg.head == :(::)
            push!(arg_names, arg.args[1])
        else
            push!(arg_names, arg)
        end
    end

    # Build the key expression (tuple of argument names)
    if length(arg_names) == 1
        key_expr = arg_names[1]
    else
        key_expr = Expr(:tuple, arg_names...)
    end

    # Generate the memoized function with original signature
    let wrapped = quote
        let cache = Dict{Any, Any}()
            function $(funcname)($(arg_exprs...))$(return_type != nothing ? :(::$return_type) : nothing)
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
const fib = @memoize function fib(n::Int)::Int
    if n <= 1
        return n
    end
    return fib(n - 1) + fib(n - 2)
end

println("fib(90) = $(fib(90))")
println("fib(90) again (cached) = $(fib(90))")