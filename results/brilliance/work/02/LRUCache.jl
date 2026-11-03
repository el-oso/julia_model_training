"""
LRUCache — a fast, O(1) least-recently-used cache. Base only.

    using .LRUCache
    c = LRU{Int,String}(100)
    c[42] = "hello"
    get(c, 42, "missing")   # hit: counts as a use, performs no allocation
    c[43] = "world"         # insert; evicts the least recently used entry when full
"""
module LRUCache

import Base: get, getindex, setindex!, haskey, length, isempty, size, empty!,
            iterate, keys, values, show

# Design: a `Dict{K, node}` gives O(1) lookup; a doubly linked list of nodes
# gives O(1) reordering and eviction. `head` is the most recently used node,
# `tail` the least recently used. Recency updates are pure pointer surgery —
# no allocation, so `get` on a present key is allocation-free.

"""A node in the doubly linked list that tracks recency order (internal)."""
mutable struct _LRUNode{K,V}
    key::K
    value::V
    prev::Union{_LRUNode{K,V},Nothing}
    next::Union{_LRUNode{K,V},Nothing}
    @inline _LRUNode{K,V}(key, value) where {K,V} = new(key, value, nothing, nothing)
end

"""
    LRU{K,V}(capacity::Integer)

A least-recently-used (LRU) cache holding at most `capacity` entries.

All operations are O(1):

- `get(cache, key, default)` / `cache[key]` — read. A hit counts as a use and
  promotes the entry to most-recently-used. A miss returns `default` and does
  not change recency order.
- `cache[key] = value` — insert or update; counts as a use. Inserting a new
  key into a full cache evicts the least recently used entry. A cache with
  `capacity == 0` stores nothing.
- `haskey(cache, key)` — membership test; does *not* count as a use.
- `length(cache)` — number of stored entries.

`get` on a present key performs no heap allocations.

# Examples
```jldoc
julia> c = LRU{Int,Int}(2)

julia> c[1] = 10; c[2] = 20;

julia> get(c, 1, -1)   # reading key 1 counts as a use
10

julia> c[3] = 30       # cache full: evicts key 2 (least recently used)

julia> haskey(c, 2)
false
```
"""
mutable struct LRU{K,V}
    capacity::Int
    size::Int
    map::Dict{K,_LRUNode{K,V}}
    head::Union{_LRUNode{K,V},Nothing}  # most recently used entry
    tail::Union{_LRUNode{K,V},Nothing}  # least recently used entry

    function LRU{K,V}(capacity::Integer) where {K,V}
        capacity < 0 && throw(ArgumentError("capacity must be >= 0, got $capacity"))
        new(Int(capacity), 0, Dict{K,_LRUNode{K,V}}(), nothing, nothing)
    end
end

"""
    LRU(capacity::Integer)

Construct an `LRU{Any,Any}` cache. Prefer the explicit `LRU{K,V}(capacity)`
form: it keeps values unboxed and keeps every operation monomorphic.
"""
LRU(capacity::Integer) = LRU{Any,Any}(capacity)

"""Insert `node` (unlinked) as the new head (most recently used)."""
@inline function _push_front(cache::LRU{K,V}, node::_LRUNode{K,V}) where {K,V}
    if cache.head === nothing
        cache.tail = node
    else
        node.next = cache.head
        cache.head.prev = node
    end
    node.prev = nothing
    cache.head = node
    return nothing
end

"""Unlink `node` (which must be in the list) and clear its links."""
@inline function _unlink(cache::LRU{K,V}, node::_LRUNode{K,V}) where {K,V}
    p = node.prev
    n = node.next
    if p === nothing
        cache.head = n
    else
        p.next = n
    end
    if n === nothing
        cache.tail = p
    else
        n.prev = p
    end
    node.prev = nothing
    node.next = nothing
    return nothing
end

"""Move `node` (in the list) to the head (most recently used)."""
@inline function _move_to_front(cache::LRU{K,V}, node::_LRUNode{K,V}) where {K,V}
    node === cache.head && return nothing
    _unlink(cache, node)
    _push_front(cache, node)
    return nothing
end

"""Remove and return the least recently used key."""
@inline function _evict(cache::LRU{K,V}) where {K,V}
    victim = cache.tail
    _unlink(cache, victim)
    pop!(cache.map, victim.key)
    cache.size -= 1
    return victim.key
end

"""
    get(cache::LRU, key, default)

Return `cache[key]` if `key` is present, else `default`.
A hit counts as a use; a miss leaves the recency order unchanged.
Does not allocate when the key is present (nor when it is absent).
"""
function get(cache::LRU{K,V}, key, default) where {K,V}
    node = get(cache.map, key, nothing)
    node === nothing && return default
    _move_to_front(cache, node)
    return node.value
end

get(f::Function, cache::LRU{K,V}, key) where {K,V} = get(cache, key, f())

"""
    getindex(cache, key)

Like `get`, but throws `KeyError` on a miss. A hit counts as a use.
"""
function getindex(cache::LRU{K,V}, key) where {K,V}
    node = get(cache.map, key, nothing)
    node === nothing && throw(KeyError(key))
    _move_to_front(cache, node)
    return node.value
end

"""
    setindex!(cache, value, key)

Insert or update `key => value`, marking it as most recently used. If the
cache is full and `key` is new, the least recently used entry is evicted.
A cache with `capacity == 0` stores nothing (the write is a no-op).
Returns `value`.
"""
function setindex!(cache::LRU{K,V}, value::V, key::K) where {K,V}
    cache.capacity == 0 && return value
    node = get(cache.map, key, nothing)
    if node === nothing
        if cache.size == cache.capacity
            _evict(cache)
        end
        node = _LRUNode{K,V}(key, value)
        cache.map[key] = node
        cache.size += 1
    else
        node.value = value
        _unlink(cache, node)
    end
    _push_front(cache, node)
    return value
end

"""
    haskey(cache, key)

Membership test. Does not count as a use.
"""
haskey(cache::LRU{K,V}, key) where {K,V} = haskey(cache.map, key)

"""    length(cache)    Number of entries currently stored."""
length(cache::LRU) = cache.size

"""    isempty(cache)   `true` if the cache holds no entries."""
isempty(cache::LRU) = cache.size == 0

size(cache::LRU) = (cache.size,)

"""    empty!(cache)    Remove all entries."""
function empty!(cache::LRU{K,V}) where {K,V}
    empty!(cache.map)
    cache.size = 0
    cache.head = nothing
    cache.tail = nothing
    return cache
end

"""
    iterate(cache)

Iterate `(key, value)` pairs from most to least recently used.
"""
iterate(cache::LRU{K,V}) where {K,V} = iterate(cache, cache.head)
iterate(cache::LRU{K,V}, node::_LRUNode{K,V}) where {K,V} = (node.key, node.value), node.next
iterate(cache::LRU{K,V}, ::Nothing) where {K,V} = nothing

"""    keys(cache)    Keys from most to least recently used (lazy)."""
keys(cache::LRU{K,V}) where {K,V} = (k for (k, v) in cache)

"""    values(cache)  Values from most to least recently used (lazy)."""
values(cache::LRU{K,V}) where {K,V} = (v for (k, v) in cache)

function show(io::IO, cache::LRU{K,V}) where {K,V}
    print(io, "LRU{", K, ", ", V, "}(capacity=", cache.capacity, ", size=", cache.size, ")")
end

export LRU

end # module
