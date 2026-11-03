function moving_average(x::Vector{Float64}, w::Int)
    n = length(x)
    out = zeros(n - w + 1)
    s = 0.0
    for i in 1:w
        s += x[i]
    end
    out[1] = s / w
    for i in 2:(n - w + 1)
        s += x[i + w - 1] - x[i - 1]
        out[i] = s / w
    end
    return out
end

# Test
x = [1.0, 2.0, 3.0, 4.0, 5.0]
println(moving_average(x, 3))  # Expected: [2.0, 3.0, 4.0]
