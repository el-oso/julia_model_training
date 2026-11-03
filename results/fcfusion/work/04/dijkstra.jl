"""
Dijkstra's shortest path with a hand-rolled binary min-heap.
Lazy approach: stale heap entries are skipped on pop (no decrease-key).
Works with any Real weight type.
"""

# --- heap operations on a flat array of (dist, node) tuples ---

function heapify_down(heap::Vector, i::Int)
    n = length(heap)
    while 2 * i <= n
        left = 2 * i
        right = 2 * i + 1
        smallest = i
        if left <= n && heap[left] < heap[smallest]
            smallest = left
        end
        if right <= n && heap[right] < heap[smallest]
            smallest = right
        end
        if smallest == i
            break
        end
        heap[i], heap[smallest] = heap[smallest], heap[i]
        i = smallest
    end
end

function heapify_up(heap::Vector, i::Int)
    while i > 1
        parent = i >> 1
        if heap[parent] <= heap[i]
            break
        end
        heap[i], heap[parent] = heap[parent], heap[i]
        i = parent
    end
end

function heap_push(heap::Vector, item)
    push!(heap, item)
    heapify_up(heap, length(heap))
end

function heap_pop(heap::Vector)
    heap[1], heap[end] = heap[end], heap[1]
    item = pop!(heap)
    if length(heap) > 1
        heapify_down(heap, 1)
    end
    return item
end

# --- Dijkstra ---

function dijkstra(adj, src)
    n = length(adj)
    dist = fill(Inf, n)
    prev = zeros(Int, n)
    dist[src] = 0.0

    # Heap stores (distance, node) tuples; < compares by distance first
    heap = [(0.0, src)]

    while !isempty(heap)
        entry = heap_pop(heap)
        d, u = entry
        if d > dist[u]
            continue  # stale
        end
        for (v, w) in adj[u]
            nd = d + w
            if nd < dist[v]
                dist[v] = nd
                prev[v] = u
                heap_push(heap, (nd, v))
            end
        end
    end

    return (dist, prev)
end

# Generic Real-weight version (uses typemax for int types)
function dijkstra(adj, src, T::Type)
    n = length(adj)
    inf = isfloat(T) ? Inf : typemax(T)
    dist = fill(inf, n)
    prev = zeros(Int, n)
    dist[src] = zero(T)

    heap = [(zero(T), src)]

    while !isempty(heap)
        entry = heap_pop(heap)
        d, u = entry
        if d > dist[u]
            continue
        end
        for (v, w) in adj[u]
            nd = d + w
            if nd < dist[v]
                dist[v] = nd
                prev[v] = u
                heap_push(heap, (nd, v))
            end
        end
    end

    return (dist, prev)
end

# --- Path reconstruction ---

function path(prev::Vector{Int}, target::Int)
    result = [target]
    while prev[target] != 0
        target = prev[target]
        push!(result, target)
    end
    reverse!(result)
    return result
end
