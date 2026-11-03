module LRUCache

export LRU

# Node stores the key, value, and links (as indices into the nodes array).
# Index 0 means null.
mutable struct Node{K,V}
    key::K
    value::V
    prev::Int
    next::Int
end

mutable struct LRU{K,V}
    capacity::Int
    map::Dict{K,Int}       # key → index into nodes
    nodes::Vector{Node{K,V}}
    head::Int              # most recently used
    tail::Int              # least recently used
    size::Int
end

function LRU{K,V}(capacity::Int) where {K,V}
    @assert capacity > 0 "capacity must be positive"
    return LRU{K,V}(capacity, Dict{K,Int}(), Node{K,V}[], 0, 0, 0)
end

LRU(capacity::Int) = LRU{Any,Any}(capacity)

# Remove node at idx from the linked list (O(1))
function _remove_node!(cache, idx)
    node = cache.nodes[idx]
    if node.prev != 0
        cache.nodes[node.prev].next = node.next
    else
        cache.head = node.next
    end
    if node.next != 0
        cache.nodes[node.next].prev = node.prev
    else
        cache.tail = node.prev
    end
    node.prev = 0
    node.next = 0
    return nothing
end

# Insert node at idx at the head of the list (O(1))
function _add_to_head!(cache, idx)
    node = cache.nodes[idx]
    node.prev = 0
    node.next = cache.head
    if cache.head != 0
        cache.nodes[cache.head].prev = idx
    end
    cache.head = idx
    if cache.tail == 0
        cache.tail = idx
    end
    return nothing
end

# Promote node at idx to most recently used (O(1))
function _promote!(cache, idx)
    if cache.head == idx
        return nothing
    end
    _remove_node!(cache, idx)
    _add_to_head!(cache, idx)
    return nothing
end

function Base.get(cache::LRU{K,V}, key::K, default::V) where {K,V}
    if Base.haskey(cache.map, key)
        idx = cache.map[key]
        _promote!(cache, idx)
        return cache.nodes[idx].value
    end
    return default
end

function Base.get(cache::LRU{K,V}, key::K) where {K,V}
    if Base.haskey(cache.map, key)
        idx = cache.map[key]
        _promote!(cache, idx)
        return cache.nodes[idx].value
    end
    throw(KeyError(key))
end

function Base.setindex!(cache::LRU{K,V}, value::V, key::K) where {K,V}
    if Base.haskey(cache.map, key)
        # Update existing entry and promote
        idx = cache.map[key]
        cache.nodes[idx].value = value
        _promote!(cache, idx)
    else
        if cache.size == cache.capacity
            # Evict least recently used
            evict_idx = cache.tail
            evict_key = cache.nodes[evict_idx].key
            delete!(cache.map, evict_key)
            _remove_node!(cache, evict_idx)
            # Reuse the evicted slot
            cache.nodes[evict_idx] = Node{K,V}(key, value, 0, 0)
            cache.map[key] = evict_idx
            _add_to_head!(cache, evict_idx)
        else
            # Insert new node
            idx = cache.size + 1
            push!(cache.nodes, Node{K,V}(key, value, 0, 0))
            cache.map[key] = idx
            _add_to_head!(cache, idx)
            cache.size += 1
        end
    end
    return nothing
end

function Base.haskey(cache::LRU{K,V}, key::K) where {K,V}
    return Base.haskey(cache.map, key)
end

function Base.length(cache::LRU)
    return cache.size
end

end
