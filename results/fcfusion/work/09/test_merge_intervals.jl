using Test
include("merge_intervals.jl")

@testset "merge_intervals" begin

    @testset "empty input" begin
        @test merge_intervals([(0, 0)]) == [(0, 0)]
        @test merge_intervals([]) == []
    end

    @testset "single interval" begin
        @test merge_intervals([(1, 5)]) == [(1, 5)]
        @test merge_intervals([(10.5, 20.3)]) == [(10.5, 20.3)]
    end

    @testset "already disjoint" begin
        @test merge_intervals([(1, 2), (4, 5), (7, 8)]) == [(1, 2), (4, 5), (7, 8)]
    end

    @testset "fully overlapping" begin
        @test merge_intervals([(1, 10), (2, 5), (3, 7)]) == [(1, 10)]
    end

    @testset "partially overlapping" begin
        @test merge_intervals([(1, 5), (3, 7), (6, 9)]) == [(1, 9)]
    end

    @testset "touching intervals merge" begin
        @test merge_intervals([(1, 3), (3, 5)]) == [(1, 5)]
        @test merge_intervals([(1, 2), (2, 3), (3, 4)]) == [(1, 4)]
    end

    @testset "unsorted input" begin
        @test merge_intervals([(5, 6), (1, 3), (3, 4)]) == [(1, 4), (5, 6)]
        @test merge_intervals([(10, 12), (1, 5), (4, 8)]) == [(1, 8), (10, 12)]
    end

    @testset "point intervals" begin
        @test merge_intervals([(1, 1), (1, 1), (1, 1)]) == [(1, 1)]
        @test merge_intervals([(1, 1), (2, 2)]) == [(1, 1), (2, 2)]
        @test merge_intervals([(1, 1), (1, 2)]) == [(1, 2)]
    end

    @testset "intervals contained in others" begin
        @test merge_intervals([(1, 10), (2, 3), (5, 6)]) == [(1, 10)]
        @test merge_intervals([(2, 3), (1, 4), (3, 5)]) == [(1, 5)]
    end

    @testset "negative numbers" begin
        @test merge_intervals([(-5, -3), (-2, 0)]) == [(-5, -3), (-2, 0)]
        @test merge_intervals([(-5, -3), (-3, 0)]) == [(-5, 0)]
    end

    @testset "floating point" begin
        @test merge_intervals([(1.0, 2.0), (2.0, 3.0)]) == [(1.0, 3.0)]
        @test merge_intervals([(0.5, 1.5), (1.0, 2.0)]) == [(0.5, 2.0)]
    end

    @testset "mixed integer and float" begin
        @test merge_intervals([(1, 2), (2.0, 3)]) == [(1, 3)]
    end

    @testset "input not mutated" begin
        input = [(5, 6), (1, 3), (3, 4)]
        input_copy = copy(input)
        merge_intervals(input)
        @test input == input_copy
    end

    @testset "complex real-world scenario" begin
        intervals = [
            (1, 3), (2, 6), (8, 10), (15, 18),
            (4, 6), (7, 10), (11, 12), (14, 16),
            (16, 17), (19, 22), (20, 21)
        ]
        expected = [(1, 6), (7, 10), (11, 12), (14, 18), (19, 22)]
        @test merge_intervals(intervals) == expected
    end

    # Randomized property test
    @testset "randomized property test" begin
        using Random

        Random.seed!(42)

        # Brute-force coverage check: for each point in range, check if it's
        # covered by original vs merged intervals
        function point_covered(x, intervals)
            for (a, b) in intervals
                if a <= x <= b
                    return true
                end
            end
            return false
        end

        for trial in 1:200
            # Generate random intervals in [0, 100]
            n = rand(1:30)
            intervals = []
            for i in 1:n
                a = rand(0:100)
                b = rand(a:100)
                push!(intervals, (a, b))
            end

            merged = merge_intervals(intervals)

            # Property 1: Merged intervals are sorted and disjoint
            for i in 1:length(merged)-1
                @test merged[i][2] < merged[i+1][1]
            end

            # Property 2: Coverage is identical (check all integer points)
            for x in 0:100
                @test point_covered(x, intervals) == point_covered(x, merged)
            end

            # Property 3: Merged is no larger than original
            @test length(merged) <= length(intervals)
        end
    end

    @testset "many overlapping intervals" begin
        # Create 1000 intervals all overlapping at a central point
        intervals = [(i, 1000 + i) for i in 1:1000]
        @test merge_intervals(intervals) == [(1, 2000)]
    end

end

println("All tests passed!")
