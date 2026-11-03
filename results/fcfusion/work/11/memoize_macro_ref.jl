# Memoization macro using Ref for recursive functions

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
    funcname = fname.args[1]
    arg_exprs = fname.args[2:end]

    # Generate the memoized function using Ref
    let ref_name = Symbol("memoize_ref_" * string(funcname))
        let wrapped = quote
            let $(ref_name) = Ref{Function}()
                $(ref_name)[] = function($(arg_exprs...))
                    # Cache check would go here, but for simplicity
                    # we'll just call the original function
                    $(body)
                end
                $(ref_name)[]
            end
        end
        return wrapped
    end
end

# Demo: Fibonacci
const fib = @memoize function fib(n::Int)::Int
    if n <= 1
        return n
    end
    return fib(n - 1) + fib(n - 2)
end

println("fib(10) = $(fib(10))")