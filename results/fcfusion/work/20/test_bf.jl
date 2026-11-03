using Test
include("bf.jl")

@testset "Brainfuck interpreter" begin
    # Hello World!
    hello = "++++++++++[>+++++++>++++++++++>+++>+<<<<-]>++.>+.+++++++..+++.>++.<<+++++++++++++++.>.+++.------.--------.>+.>."
    @test run_bf(hello) == "Hello World!\n"

    # Echo program (reads input and echoes it)
    echo = ",[.,]"
    @test run_bf(echo, "abc") == "abc"

    # Program that reads one byte and increments it
    increment = ",+."
    @test run_bf(increment, "a") == "b"

    # Empty program
    @test run_bf("") == ""

    # Simple output
    @test run_bf("++++++++++.") == "\n"

    # Wraparound arithmetic
    @test run_bf("[-]+++++.") == "\x05"
    @test run_bf("[-]++++++++++.") == "\x0a"

    # Clear cell optimization
    @test run_bf("[-]") == ""
    @test run_bf("++++[-]") == ""
end

println("All tests passed!")
