using Test
include(joinpath(@__DIR__, "..", "LRUCache.jl"))
using .LRUCache

@testset "LRU cache" begin

@testset "constructor" begin
    @test LRU{Int,Int}(4).capacity == 4
    @test length(LRU{Int,Int}(4)) == 0
    @test isempty(LRU{Int,Int}(4))
    @test size(LRU{Int,Int}(4)) == (0,)
    @test_throws ArgumentError LRU{Int,Int}(-1)
    @test LRU(3) isa LRU{Any,Any}
    @test sprint(show, LRU{Int,Int}(4)) == "LRU{Int64, Int64}(capacity=4, size=0)"
end

@testset "basic set/get/haskey/length" begin
    c = LRU{Int,Int}(3)
    @test get(c, 1, -1) == -1          # miss
    c[1] = 10
    c[2] = 20
    @test get(c, 1, -1) == 10          # hit
    @test get(c, 2, -1) == 20
    @test get(c, 3, -1) == -1          # miss
    @test c[1] == 10
    @test_throws KeyError c[3]
    @test haskey(c, 1)
    @test haskey(c, 2)
    @test !haskey(c, 3)
    @test length(c) == 2
    @test size(c) == (2,)
    @test !isempty(c)
    @test get(c, 1, nothing) === 10
    @test get(() -> -42, c, 1) == 10
    @test get(() -> -42, c, 9) == -42
    @test (c[2] = 21) == 21            # setindex! returns the value
end

@testset "recency: reads and writes refresh, misses and haskey do not" begin
    # a read refreshes
    c = LRU{Int,Int}(2)
    c[1] = 1
    c[2] = 2
    get(c, 1, 0)        # 1 becomes MRU, 2 is LRU
    c[3] = 3            # evicts 2
    @test !haskey(c, 2)
    @test haskey(c, 1)
    @test haskey(c, 3)
    @test length(c) == 2

    # a write to an existing key also refreshes
    c = LRU{Int,Int}(2)
    c[1] = 1
    c[2] = 2
    c[1] = 100          # update; 1 becomes MRU
    c[3] = 3            # evicts 2
    @test get(c, 1, -1) == 100
    @test !haskey(c, 2)

    # a miss does not change recency
    c = LRU{Int,Int}(2)
    c[1] = 1
    c[2] = 2
    get(c, 99, 0)       # miss
    c[3] = 3            # evicts 1
    @test !haskey(c, 1)
    @test haskey(c, 2)
    @test haskey(c, 3)

    # haskey does not refresh
    c = LRU{Int,Int}(2)
    c[1] = 1
    c[2] = 2
    haskey(c, 1)
    c[3] = 3            # evicts 1
    @test !haskey(c, 1)
    @test haskey(c, 2)
    @test haskey(c, 3)
end

@testset "updates do not grow the cache" begin
    c = LRU{Int,Int}(2)
    c[1] = 1
    c[1] = 2
    c[1] = 3
    @test length(c) == 1
    @test get(c, 1, 0) == 3
end

@testset "eviction order (full sweep)" begin
    c = LRU{Symbol,String}(3)
    c[:a] = "a"
    c[:b] = "b"
    c[:c] = "c"
    c[:d] = "d"    # evicts :a
    @test !haskey(c, :a)
    c[:b] = "B"    # refresh :b -> MRU
    c[:e] = "e"    # evicts :c
    @test !haskey(c, :c)
    c[:f] = "f"    # evicts :d
    @test !haskey(c, :d)
    @test collect(c) == [(:f, "f"), (:e, "e"), (:b, "B")]
end

@testset "value types" begin
    c = LRU{Int,Vector{Float64}}(2)
    v = [1.0, 2.0]
    c[1] = v
    @test get(c, 1, nothing) === v      # stored by reference, returned as-is
    c[1] = [3.0]
    @test get(c, 1, nothing) == [3.0]
    @test get(c, 1, nothing) !== v

    s = LRU{String,Any}(3)
    s["x"] = 1
    s["y"] = "two"
    s["z"] = 3.0
    @test get(s, "x", nothing) === 1
    @test get(s, "y", nothing) === "two"
    @test get(s, "z", nothing) === 3.0
end

@testset "capacity zero" begin
    c = LRU{Int,Int}(0)
    c[1] = 1
    @test isempty(c)
    @test get(c, 1, -1) == -1
    @test !haskey(c, 1)
end

@testset "empty!" begin
    c = LRU{Int,Int}(3)
    c[1] = 1
    c[2] = 2
    empty!(c)
    @test isempty(c)
    @test length(c) == 0
    @test collect(c) == []
    c[3] = 30
    @test get(c, 3, 0) == 30
    @test length(c) == 1
end

@testset "iteration order is MRU-first" begin
    c = LRU{Int,Int}(4)
    c[1] = 1
    c[2] = 2
    c[3] = 3
    @test collect(c) == [(3, 3), (2, 2), (1, 1)]
    get(c, 1, 0)
    @test collect(c) == [(1, 1), (3, 3), (2, 2)]
    @test collect(keys(c)) == [1, 3, 2]
    @test collect(values(c)) == [1, 3, 2]
end

@testset "no allocation on get (hit and miss)" begin
    c = LRU{Int,Int}(8)
    for i in 1:8
        c[i] = 10 * i
    end
    # warm up: compile every path before measuring
    get(c, 1, 0)      # hit on a non-MRU entry (list move)
    get(c, 8, 0)      # hit on the MRU entry
    get(c, 1234, 0)   # miss
    c[1] = 10         # update of an existing key
    GC.gc()
    @test @allocated(get(c, 8, 0)) == 0
    @test @allocated(get(c, 5, 0)) == 0
    @test @allocated(get(c, 1234, 0)) == 0
    @test @allocated(c[5]) == 0
    @test @allocated(c[5] = 50) == 0   # update of an existing key
    @test @allocated(haskey(c, 5)) == 0
    @test @allocated(haskey(c, 1234)) == 0
    @test @allocated(length(c)) == 0
end

@testset "randomized reference model" begin
    # Small deterministic LCG: self-contained, no Random dependency.
    seed = Ref(Int(0x5eed))
    rand_() = (seed[] = (1103515245 * seed[] + 12345) % (2 ^ 31); seed[] % 2 ^ 31)
    capacity = 5
    c = LRU{Int,Int}(capacity)
    ref = Dict{Int,Int}()
    recency = Int[]   # recency[1] = MRU, end = LRU

    for i in 1:5000
        k = 1 + rand_() % 10
        if rand_() % 100 <= 65
            v = rand_() % 1000
            c[k] = v
            ref[k] = v
            filter!(x -> x != k, recency)
            pushfirst!(recency, k)
            while length(recency) > capacity
                delete!(ref, pop!(recency))
            end
        else
            @test get(c, k, nothing) === get(ref, k, nothing)
            if haskey(ref, k)
                filter!(x -> x != k, recency)
                pushfirst!(recency, k)
            end
        end
        @test length(c) == length(ref)
        @test haskey(c, k) == haskey(ref, k)
        @test collect(keys(c)) == recency
    end
end

@testset "O(1) scaling" begin
    # Steady-state throughput of (insert-new-key + get) with a window of
    # capacity+1 distinct keys, so every insert evicts. If operations were
    # O(n) (e.g. scanning for the LRU entry), per-op time would grow linearly
    # with capacity; O(1) allows only mild memory/cache effects.
    function ops_per_second(capacity, n_ops)
        c = LRU{Int,Int}(capacity)
        for i in 1:capacity   # fill to steady state
            c[i] = i
        end
        for i in 1:10_000    # warm up / compile
            k = (i - 1) % (capacity + 1) + 1
            c[k] = i
            get(c, k, 0)
        end
        t0 = time_ns()
        for i in 1:n_ops
            k = (i - 1) % (capacity + 1) + 1
            c[k] = i
            get(c, k, 0)
        end
        return n_ops / ((time_ns() - t0) / 1e9)
    end
    small = ops_per_second(2 ^ 15, 400_000)
    large = ops_per_second(2 ^ 17, 400_000)
    @info "throughput" small_ops_per_s = small large_ops_per_s = large ratio = small / large
    # 4x the working set must not cost 4x per op (that would be O(n) per op);
    # memory effects alone give at most ~2-3x here.
    @test small / large < 4
end

end
