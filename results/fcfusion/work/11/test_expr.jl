# Debug: print the expr inside the macro

macro memoize(expr)
    println("=== expr ===")
    show(expr)
    println("=== end expr ===")

    # Parse the function definition
    if expr.head == :function
        fname = expr.args[1]
        body = expr.args[2]
        println("fname: ", fname)
        println("body: ", body)
    elseif expr.head == :(=)
        fname = expr.args[1]
        body = expr.args[2]
        println("fname: ", fname)
        println("body: ", body)
    else
        error("@memoize expects a function definition")
    end

    # Return the original expr for now
    return expr
end

fib = @memoize function fib(n::Int)::Int
    if n <= 1
        return n
    end
    return fib(n - 1) + fib(n - 2)
end

println("fib(10) = $(fib(10))")