# Test: simple macro that just returns the function
macro passthrough(expr)
    return expr
end

fib = @passthrough function fib(n::Int)::Int
    if n <= 1
        return n
    end
    return fib(n - 1) + fib(n - 2)
end

println("fib(10) = $(fib(10))")