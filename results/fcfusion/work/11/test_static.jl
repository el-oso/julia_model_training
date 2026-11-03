# Test: static variable in a function

function counter()
    static count = 0
    count = count + 1
    return count
end

println(counter())
println(counter())
println(counter())