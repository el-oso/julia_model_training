"""
    merge_intervals(intervals)

Merge a collection of closed intervals.

Given a vector of `(start, stop)` tuples representing closed intervals (where
`start ≤ stop`), returns the minimal sorted list of disjoint intervals that
cover exactly the same set of points. Touching intervals are merged.

# Arguments
- `intervals`: Vector of tuples `(a, b)` where `a ≤ b` and both are `Real`.

# Returns
- Vector of merged, disjoint, sorted intervals as `(a, b)` tuples.

# Complexity
O(n log n) due to sorting; the merge pass is O(n).

# Notes
- The input is not mutated.
- Duplicate and fully contained intervals are collapsed.
- Touching intervals (e.g., `[1, 3]` and `[3, 5]`) are merged into `[1, 5]`.
"""
function merge_intervals(intervals)
    if isempty(intervals)
        return typeof(intervals)()
    end

    # Sort by start, breaking ties by end (descending so larger intervals come first)
    sorted = sort(intervals, by = x -> (x[1], -x[2]))

    merged = Vector{typeof(sorted[1])}(undef, 0)
    current = sorted[1]

    for interval in sorted[2:end]
        if interval[1] <= current[2]
            # Overlapping or touching: extend current
            current = (current[1], max(current[2], interval[2]))
        else
            # Disjoint: push current and start new
            push!(merged, current)
            current = interval
        end
    end
    push!(merged, current)

    return merged
end
