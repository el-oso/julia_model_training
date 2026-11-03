# Debug: parse function definition and print components

macro memoize_debug(expr)
    # Parse the function definition
    if expr.head == :function
        fname = expr.args[1]
        body = expr.args[2]
        println("fname: ", fname)
        println("fname.args: ", fname.args)
        println("body: ", body)
    elseif expr.head == :(=)
        fname = expr.args[1]
        body = expr.args[2]
        println("fname: ", fname)
        println("fname.args: ", fname.args)
        println("body: ", body)
    else
        error("@memoize expects a function definition")
    end

    # Return the original expr
    return expr
end

@memoize_debug function fib(n::Int)::Int
    if n <= 1
        return n
    end
    return fib(n - 1) + fib(n - 2)
end