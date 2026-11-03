# Memoization macro for Julia
# Usage: fib = @memoize function fib(n::Int)::Int ... end

macro memoize(expr)
    # Parse function definition (both `function f(...) ... end` and `f(x) = ...` forms)
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

    # Extract argument names and types
    arg_names = []
    arg_types = []
    all_concrete = true

    for arg in arg_exprs
        if arg.head == :(::)
            push!(arg_names, arg.args[1])
            push!(arg_types, arg.args[2])
        else
            push!(arg_names, arg)
            push!(arg_types, Any)
            all_concrete = false
        end
    end

    # Build cache type: Dict{Key, Any} where Key is the arg type (or tuple)
    if length(arg_types) == 1
        if all_concrete
            cache_type = Expr(:curly, :Dict, arg_types[1], :Any)
        else
            cache_type = Expr(:curly, :Dict, :Any, :Any)
        end
        key_expr = arg_names[1]
    else
        if all_concrete
            tuple_type = Expr(:curly, :Tuple, arg_types...)
            cache_type = Expr(:curly, :Dict, tuple_type, :Any)
        else
            cache_type = Expr(:curly, :Dict, :Any, :Any)
        end
        key_expr = Expr(:tuple, arg_names...)
    end

    # Generate: let cache = Dict{...}(); function f(args) ... end; f; end
    let wrapped = quote
        let cache = $(cache_type)()
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

# Debug: show what the macro generates
fib_expr = @memoize function fib(n::Int)::Int
    if n <= 1
        return n
    end
    return fib(n - 1) + fib(n - 2)
end

println("Generated expression:")
println(fib_expr)
println()

# Now actually define fib
fib = @memoize function fib(n::Int)::Int
    if n <= 1
        return n
    end
    return fib(n - 1) + fib(n - 2)
end

println("fib(90) = $(fib(90))")
println("fib(90) again (cached) = $(fib(90))")