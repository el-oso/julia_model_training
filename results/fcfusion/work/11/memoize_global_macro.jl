# Memoization macro with global cache

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

    # Extract function name and arguments
    func_sig = fname.args[1]
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

    # Generate the cache declaration and function definition
    let cache_name = Symbol("memoize_cache_" * string(funcname))
        let wrapped = Expr(:block,
            Expr(:const, Expr(:(=), cache_name, Expr(:call, :Dict{Any, Any}))),
            Expr(:function, fname, quote
                local key = $(key_expr)
                if haskey($(cache_name), key)
                    return $(cache_name)[key]
                end
                local result = $(body)
                $(cache_name)[key] = result
                return result
            end)
        )
        return esc(wrapped)
    end
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