# Test: can a SINGLE recursive function (1 frame/level) with a moderate number
# of locals survive 50k levels? This tells us if "merge everything into one
# recursive function" is viable for stack safety.
function big(n::Int, a::Float64, b::Float64, c::Float64, d::Float64, e::Float64,
             f::Float64, g::Float64, h::Float64, i2::Int, j::Int, k::Int)
    if n == 0
        return a + b + c + d + e + f + g + h + i2 + j + k
    end
    x = a * 1.0000001
    y = b * 1.0000002
    z = c + d
    w = e - f
    # simulate real work with several temporaries
    t1 = x + y
    t2 = z * w
    t3 = t1 + t2
    t4 = h / (t3 + 1.0)
    return big(n - 1, t4, b, c, d, e, f, g, h, i2, j, k)
end

for d in [10_000, 20_000, 30_000, 50_000]
    try
        v = big(d, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 1, 2, 3)
        println("depth $d: OK ($v)")
    catch e
        if e isa StackOverflowError
            println("depth $d: STACK OVERFLOW")
        else
            println("depth $d: ERR $e")
        end
    end
end
