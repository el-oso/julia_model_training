using Test

"""
    merge_intervals(v) -> Vector of (start, stop) tuples

Given a vector of closed `(start, stop)` tuples (any `Real` type, unsorted),
return the minimal sorted list of disjoint intervals covering the same points.
Touching intervals are merged. O(n log n). Does not mutate the input.
"""
function merge_intervals(v)
    isempty(v) && return Tuple{Int, Int}[]
    
    # Sort by start point; break ties by stop descending so touching
    # intervals (a,b) and (b,c) merge correctly regardless of order.
    sorted = sort(v, by = x -> x[1])
    
    result = Tuple{eltype(sorted[1][1]), eltype(sorted[1][2])}[]
    push!(result, sorted[1])
    
    for interval in sorted[2:end]
        last = result[end]
        if interval[1] <= last[2]
            # Overlap or touching: extend
            result[end] = (last[1], max(last[2], interval[2]))
        else
            # Disjoint: start new interval
            push!(result, interval)
        end
    end
    
    return result
end

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@testset "merge_intervals" begin

    # --- Basic correctness ---

    @test merge_intervals([]) == Tuple{Int, Int}[]

    @test merge_intervals([(1, 3), (2, 6), (8, 10), (15, 23)]) ==
          [(1, 6), (8, 10), (15, 23)]

    @test merge_intervals([(1, 4), (4, 5)]) == [(1, 5)]   # touching

    @test merge_intervals([(1, 2), (3, 4)]) == [(1, 2), (3, 4)]  # no overlap

    @test merge_intervals([(5, 10), (1, 3)]) == [(1, 3), (5, 10)]  # unsorted input

    @test merge_intervals([(1, 10)]) == [(1, 10)]  # single interval

    # --- Containment / nesting ---

    @test merge_intervals([(1, 10), (2, 5)]) == [(1, 10)]

    @test merge_intervals([(1, 10), (2, 5), (6, 9)]) == [(1, 10)]

    @test merge_intervals([(1, 4), (3, 6), (5, 8)]) == [(1, 8)]

    # --- Identical intervals ---

    @test merge_intervals([(1, 3), (1, 3), (1, 3)]) == [(1, 3)]

    # --- Degenerate (point) intervals ---

    @test merge_intervals([(5, 5), (5, 5)]) == [(5, 5)]
    @test merge_intervals([(5, 5), (4, 6)]) == [(4, 6)]
    @test merge_intervals([(5, 5), (6, 6)]) == [(5, 5), (6, 6)]

    # --- Floating-point intervals ---

    @test merge_intervals([(1.0, 3.0), (2.0, 4.0)]) == [(1.0, 4.0)]
    @test merge_intervals([(1.5, 3.5), (3.5, 5.5)]) == [(1.5, 5.5)]  # touching floats

    # --- Negative intervals ---

    @test merge_intervals([(-5, -1), (-3, 2), (2, 4)]) == [(-5, 4)]

    # --- Output is sorted and disjoint ---

    result = merge_intervals([(3, 5), (1, 2), (6, 8), (4, 6)])
    @test all(i <= j for (i, j) in result)
    @test all(j < k for ((i, j), (k, l)) in zip(result, result[2:end]))

    # --- No mutation of input ---

    v = [(3, 5), (1, 2), (6, 8)]
    v_copy = copy(v)
    merge_intervals(v)
    @test v == v_copy

    # -----------------------------------------------------------------------
    # Property tests: randomized brute-force verification
    # -----------------------------------------------------------------------

    function brute_force_union(intervals)
        isempty(intervals) && return Tuple{eltype(first(intervals)[1]), eltype(first(intervals)[2])}[]
        # Sort by start, break ties by stop descending (same strategy as merge_intervals)
        sorted = sort(intervals, by = x -> x[1])
        T = Tuple{eltype(sorted[1][1]), eltype(sorted[1][2])}
        out = T[]
        push!(out, sorted[1])
        for iv in sorted[2:end]
            last = out[end]
            if iv[1] <= last[2]
                out[end] = (last[1], max(last[2], iv[2]))
            else
                push!(out, iv)
            end
        end
        return out
    end

    function points_covered(intervals::Vector{Tuple{Int, Int}})
        s = BitSet()
        for (a, b) in intervals
            for i in a:b
                push!(s, i)
            end
        end
        return s
    end

    function check_properties(result::Vector{Tuple{Int, Int}}, points::BitSet)
        # 1. Every output interval lies within [min_start, max_stop]
        !isempty(result) && @test all(
            first(iv) >= minimum(first, result) && last(iv) <= maximum(last, result)
            for iv in result
        )

        # 2. Disjoint: no two intervals overlap or touch
        for i in 1:length(result)-1
            @test last(result[i]) < first(result[i+1])
        end

        # 3. Minimal: every interval boundary is "needed"
        #    (removing any interval would lose points)
        for (idx, iv) in enumerate(result)
            others = Tuple{Int, Int}[]
            for j in 1:length(result)
                j != idx && push!(others, result[j])
            end
            @test !(BitSet(iv[1]:iv[2]) ⊆ points_covered(others))
        end
    end

    @testset "randomized property tests" begin
        for _ in 1:500
            n = rand(1:20)
            raw = Tuple{Int, Int}[]
            for _ in 1:n
                a = rand(-100:100)
                b = a + rand(0:100)
                push!(raw, (a, b))
            end

            expected = brute_force_union(raw)
            result = merge_intervals(raw)

            @test result == expected

            # Property: coverage matches brute force exactly
            @test points_covered(result) == points_covered(raw)

            # Property: sorted by start
            @test all(i <= j for (i, j) in result)

            # Property: disjoint (no overlap or touching between consecutive)
            @test all(j < k for ((i, j), (k, l)) in zip(result, result[2:end]))
        end
    end

    @testset "randomized property tests with floats" begin
        for _ in 1:200
            n = rand(1:10)
            raw = Tuple{Float64, Float64}[]
            for _ in 1:n
                a = rand(-50.0:50.0)
                b = a + rand(0.0:50.0)
                push!(raw, (a, b))
            end

            expected = brute_force_union(raw)
            result = merge_intervals(raw)
            @test result == expected

            # Property: sorted and disjoint
            @test all(i <= j for (i, j) in result)
            @test all(j < k for ((i, j), (k, l)) in zip(result, result[2:end]))
        end
    end

end
