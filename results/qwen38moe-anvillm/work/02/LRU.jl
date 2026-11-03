# LRU cache — Base only, O(1) per operation, `get` on present key allocates nothing.
#
# Usage:
#   cache = LRU{String, Int}(3)
#   cache["a"] = 1
#   get(cache, "a", -1)   → 1  (touches "a", moves to MRU)
#   haskey(cache, "a")     → true
#   length(cache)          → 3
#
# Internals: slot pool `nodes::Vector{Union{Nothing, Node}}` (one per capacity slot),
# `key_to_idx::Dict{K,Int}` for O(1) lookup, doubly-linked list via head/tail.

mutable struct Node{K,V}
    key::K
    value::V
    prev::Int   # 0 = no previous
    next::Int   # 0 = no next
end

mutable struct LRU{K,V}
    capacity::Int
    nodes::Vector{Union{Nothing, Node{K,V}}}  # slot pool; nothing = free
    key_to_idx::Dict{K,Int}
    head::Int  # index of first node (0 = empty)
    tail::Int  # index of last node  (0 = empty)
end

"""
    LRU{K,V}(capacity)

Create an LRU cache with at most `capacity` entries.
"""
function LRU{K,V}(capacity::Integer) where {K,V}
    sz = Int(capacity)
    @assert sz > 0 "capacity must be positive, got $sz"
    nodes = Vector{Union{Nothing, Node{K,V}}}(nothing, sz)
    LRU{K,V}(sz, nodes, Dict{K,Int}(), 0, 0)
end

# ── internal linked-list helpers ────────────────────────────────────────────────

# Unlink node at `idx` from the list. Caller guarantees node is in list.
function _unlink!(cache, idx)
    node = cache.nodes[idx]
    if node.prev != 0
        cache.nodes[node.prev].next = node.next
    else
        cache.head = node.next  # node was head
    end
    if node.next != 0
        cache.nodes[node.next].prev = node.prev
    else
        cache.tail = node.prev  # node was tail
    end
end

# Move node at `idx` to the front (MRU). No allocation.
function _touch!(cache::LRU{K,V}, idx::Int) where {K,V}
    node = cache.nodes[idx]
    node.prev == 0 && return  # already at front
    _unlink!(cache, idx)
    _insert_front!(cache, idx)
end

# Insert node at `idx` at the front of the list.
function _insert_front!(cache, idx)
    node = cache.nodes[idx]
    node.prev = 0
    node.next = cache.head
    if cache.head != 0
        cache.nodes[cache.head].prev = idx  # fix old head's prev
    end
    cache.head = idx
    if cache.tail == 0
        cache.tail = idx  # list was empty
    end
end

# Find first free slot. O(capacity) worst case, amortised O(1).
function _find_free(cache::LRU)
    for i in 1:cache.capacity
        cache.nodes[i] === nothing && return i
    end
    error("no free slot")
end

# Evict LRU (current tail), replace with `key, val`, move to front.
function _evict_and_insert!(cache::LRU{K,V}, key::K, val::V) where {K,V}
    tail = cache.tail
    node = cache.nodes[tail]
    old_key = node.key
    delete!(cache.key_to_idx, old_key)
    _unlink!(cache, tail)
    node.key = key
    node.value = val
    _insert_front!(cache, tail)
    cache.key_to_idx[key] = tail
    return tail
end

# ── public API ──────────────────────────────────────────────────────────────────

"""
    get(cache::LRU, key, default)

Return value for `key`, or `default` if absent.
A present key is touched (moved to MRU). O(1), no allocation on hit.
"""
function Base.get(cache::LRU{K,V}, key::K, default) where {K,V}
    idx = get(cache.key_to_idx, key, 0)
    if idx == 0
        return default
    end
    _touch!(cache, idx)
    return cache.nodes[idx].value
end

"""
    getindex(cache::LRU, key)

Convenience: `get(cache, key, missing)` — throws if absent.
"""
function Base.getindex(cache::LRU{K,V}, key::K) where {K,V}
    idx = get(cache.key_to_idx, key, 0)
    if idx == 0
        throw(KeyError(key))
    end
    _touch!(cache, idx)
    return cache.nodes[idx].value
end

"""
    setindex!(cache::LRU, value, key)

Insert or update `key → value`. Evicts LRU if full. O(1).
"""
function Base.setindex!(cache::LRU{K,V}, val::V, key::K) where {K,V}
    idx = get(cache.key_to_idx, key, 0)
    if idx != 0
        cache.nodes[idx].value = val
        _touch!(cache, idx)
    elseif length(cache) < cache.capacity
        idx = _find_free(cache)
        cache.nodes[idx] = Node{K,V}(key, val, 0, 0)
        _insert_front!(cache, idx)
        cache.key_to_idx[key] = idx
    else
        _evict_and_insert!(cache, key, val)
    end
end

"""
    haskey(cache::LRU, key)

Whether `key` is present. Does not touch. O(1).
"""
Base.haskey(cache::LRU, key) = haskey(cache.key_to_idx, key)

"""
    length(cache::LRU)

Number of keys currently stored. O(1).
"""
Base.length(cache::LRU) = length(cache.key_to_idx)

"""
    isempty(cache::LRU)

True when the cache stores no keys. O(1).
"""
Base.isempty(cache::LRU) = isempty(cache.key_to_idx)

"""
    empty!(cache::LRU)

Remove all entries. O(capacity).
"""
function Base.empty!(cache::LRU{K,V}) where {K,V}
    empty!(cache.key_to_idx)
    cache.head = 0
    cache.tail = 0
    cache.nodes .= nothing
    return cache
end

"""
    keys(cache::LRU) / values(cache::LRU)

Iterate in most-recent → least-recent order.
"""
Base.keys(cache::LRU) = _Iter(cache, Val(:key))
Base.values(cache::LRU) = _Iter(cache, Val(:value))

struct _Iter{K,V,F}
    cache::LRU{K,V}
    field::Val{F}
end
Base.eltype(::Type{_Iter{K,V,F}}) where {K,V,F} = F === :key ? K : V
Base.IteratorSize(::Type{_Iter{K,V,F}}) where {K,V,F} = Base.HasLength()
Base.IteratorSize(::Type{_Iter}) = Base.HasLength()
Base.length(iter::_Iter) = length(iter.cache.key_to_idx)

function Base.iterate(iter::_Iter{K,V,F}, state=iter.cache.head) where {K,V,F}
    state == 0 && return nothing
    slot = iter.cache.nodes[state]
    @assert slot !== nothing "iteration hit free slot"
    node = slot  # type-stable: slot is Node{K,V} here
    val = iter.field == Val(:key) ? node.key : node.value
    return val, node.next
end

# ── tests ───────────────────────────────────────────────────────────────────────

using Test

@testset "LRU" begin
    @testset "basics" begin
        c = LRU{String, Int}(3)
        @test isempty(c); @test length(c) == 0
        c["a"] = 1; c["b"] = 2; c["c"] = 3
        @test length(c) == 3
        @test c["a"] == 1; @test c["b"] == 2; @test c["c"] == 3
    end

    @testset "eviction" begin
        c = LRU{String, Int}(3)
        c["a"] = 1; c["b"] = 2; c["c"] = 3
        c["d"] = 4  # evicts a (LRU)
        @test length(c) == 3
        @test !haskey(c, "a")
        @test haskey(c, "b"); @test haskey(c, "c"); @test haskey(c, "d")
        @test c["b"] == 2; @test c["c"] == 3; @test c["d"] == 4
    end

    @testset "touch on get" begin
        c = LRU{String, Int}(3)
        c["a"] = 1; c["b"] = 2; c["c"] = 3
        get(c, "a", -1)  # touch a → a MRU, b LRU
        c["d"] = 4
        @test length(c) == 3
        @test !haskey(c, "b")  # b evicted
        @test haskey(c, "a"); @test haskey(c, "c"); @test haskey(c, "d")
        @test c["a"] == 1; @test c["c"] == 3; @test c["d"] == 4
    end

    @testset "get with default" begin
        c = LRU{String, Int}(2)
        @test get(c, "x", "MISS") == "MISS"
        c["a"] = 1; c["b"] = 2
        @test get(c, "a", "MISS") == 1
        @test get(c, "c", "MISS") == "MISS"
    end

    @testset "update existing key" begin
        c = LRU{String, Int}(3)
        c["a"] = 1; c["b"] = 2; c["a"] = 99
        @test c["a"] == 99; @test length(c) == 2  # two unique keys only
    end

    @testset "clear" begin
        c = LRU{String, Int}(3)
        c["a"] = 1; c["b"] = 2; c["c"] = 3
        empty!(c)
        @test isempty(c); @test length(c) == 0; @test get(c, "a", 0) == 0
    end

    @testset "iteration order" begin
        c = LRU{String, Int}(5)
        c["a"]=1; c["b"]=2; c["c"]=3; c["d"]=4; c["e"]=5
        @test collect(keys(c)) == ["e","d","c","b","a"]
        @test collect(values(c)) == [5,4,3,2,1]
    end

    @testset "iteration after touch" begin
        c = LRU{String, Int}(3)
        c["a"]=1; c["b"]=2; c["c"]=3
        get(c, "a", 0)
        @test collect(keys(c)) == ["a","c","b"]
    end

    @testset "capacity 1" begin
        c = LRU{Int, String}(1)
        c[1] = "one"; c[1] = "uno"
        @test c[1] == "uno"; @test length(c) == 1
        c[2] = "two"
        @test !haskey(c, 1); @test haskey(c, 2); @test c[2] == "two"
    end

    @testset "no-alloc on get" begin
        c = LRU{String, Int}(3)
        c["a"]=1; c["b"]=2; c["c"]=3
        @test (@allocated get(c, "b", 0)) == 0
    end

    @testset "eviction then insert again" begin
        c = LRU{Int, Int}(2)
        c[1]=10; c[2]=20
        @test collect(keys(c)) == [2,1]
        c[1]=100  # update 1 → touches it → MRU
        @test collect(keys(c)) == [1,2]
        c[3]=30    # evicts 2
        @test haskey(c, 1); @test haskey(c, 3); @test !haskey(c, 2)
        @test c[1]==100; @test c[3]==30
    end

    @testset "get absent key does not add it" begin
        c = LRU{String, Int}(2)
        c["x"]=1; c["y"]=2
        @test length(c) == 2
        get(c, "z", 0)
        @test length(c) == 2
        @test !haskey(c, "z")
    end
end
