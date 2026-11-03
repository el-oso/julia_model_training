include("../src/lru.jl")
using .LRUCache: LRU
using Test

@testset "LRU Cache" begin

    @testset "Basic get/set" begin
        cache = LRU{String,Int}(3)
        cache["a"] = 1
        cache["b"] = 2
        @test get(cache, "a", 0) == 1
        @test get(cache, "b", 0) == 2
        @test get(cache, "c", 99) == 99
    end

    @testset "Eviction" begin
        cache = LRU{Int,Int}(2)
        cache[1] = 10
        cache[2] = 20
        cache[3] = 30  # evicts key 1
        @test !haskey(cache, 1)
        @test get(cache, 2, 0) == 20
        @test get(cache, 3, 0) == 30
    end

    @testset "Access updates recency" begin
        cache = LRU{Int,Int}(2)
        cache[1] = 10
        cache[2] = 20
        get(cache, 1, 0)  # promote key 1
        cache[3] = 30     # evicts key 2 (least recently used)
        @test !haskey(cache, 2)
        @test get(cache, 1, 0) == 10
        @test get(cache, 3, 0) == 30
    end

    @testset "Update existing key" begin
        cache = LRU{String,Int}(2)
        cache["a"] = 1
        cache["b"] = 2
        cache["a"] = 11   # update value and promote
        @test get(cache, "a", 0) == 11
        cache["c"] = 3    # evicts key "b"
        @test !haskey(cache, "b")
        @test haskey(cache, "a")
        @test haskey(cache, "c")
    end

    @testset "haskey" begin
        cache = LRU{Int,Int}(3)
        cache[1] = 10
        @test haskey(cache, 1)
        @test !haskey(cache, 2)
    end

    @testset "length" begin
        cache = LRU{Int,Int}(5)
        @test length(cache) == 0
        cache[1] = 10
        @test length(cache) == 1
        cache[2] = 20
        @test length(cache) == 2
        cache[3] = 30
        cache[4] = 40
        cache[5] = 50
        @test length(cache) == 5
        cache[6] = 60  # evicts key 1, length stays 5
        @test length(cache) == 5
    end

    @testset "Type parameters" begin
        cache = LRU{String,Float64}(2)
        cache["pi"] = 3.14
        cache["e"] = 2.718
        @test typeof(get(cache, "pi", 0.0)) == Float64
    end

    @testset "No allocation on get hit" begin
        cache = LRU{Int,Int}(10)
        cache[1] = 100
        # Warm up
        get(cache, 1, 0)
        # Measure allocations on subsequent get
        allocs = @allocated get(cache, 1, 0)
        @test allocs == 0
    end

    @testset "get throws KeyError when missing" begin
        cache = LRU{Int,Int}(3)
        @test_throws KeyError get(cache, 1)
    end

    @testset "Full eviction cycle" begin
        cache = LRU{Int,Int}(3)
        for i in 1:10
            cache[i] = i * 10
        end
        # Only 8, 9, 10 should remain
        @test !haskey(cache, 7)
        @test get(cache, 8, 0) == 80
        @test get(cache, 9, 0) == 90
        @test get(cache, 10, 0) == 100
    end

    @testset "Interleaved access pattern" begin
        cache = LRU{Int,Int}(3)
        cache[1] = 10
        cache[2] = 20
        cache[3] = 30
        get(cache, 1, 0)  # promote 1
        get(cache, 2, 0)  # promote 2
        cache[4] = 40     # evicts 3
        @test !haskey(cache, 3)
        @test haskey(cache, 1)
        @test haskey(cache, 2)
        @test haskey(cache, 4)
    end

end
