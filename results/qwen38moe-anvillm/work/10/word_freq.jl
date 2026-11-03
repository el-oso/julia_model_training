#!/usr/bin/env julia
"""
Word frequency counter using Threads.@spawn — race-free by design.

Usage:  julia word_freq.jl <directory>

Each spawned task owns its *own* Dict{String,UInt64}. No mutable state is
shared between tasks, so there are zero data races to worry about.  The merge
is a single-threaded `for` loop on the main task after all `fetch` calls
return.

Words = lowercased Unicode-letter runs (\\p{L}+).
"""

using Unicode, Printf

function word_freq(dir::AbstractString)
    # Collect .txt files
    files = filter(f -> endswith(f, ".txt"), readdir(dir, join=true))
    # On Linux, readdir(dir, join=true) already returns "dir/file",
    # so joining again would double-append the directory. Just use as-is.
    files = [f for f in files]

    n = length(files)
    @printf("Scanning %d .txt file(s) across %d threads...\n", n, Threads.nthreads())

    # ── Spawn tasks ─────────────────────────────────────────────────────
    # Each task works on its own local Dict → no shared mutable state →
    # no data races, period.
    tasks = [Threads.@spawn _count_file(f) for f in files]

    # ── Merge (single-threaded, after all tasks are done) ───────────────
    global_counts = Dict{String,UInt64}()
    for t in tasks
        local_counts = fetch(t)            # blocks until this task finishes
        for (word, count) in local_counts
            global_counts[word] = get(global_counts, word, 0) + count
        end
    end

    # ── Print top 20 ────────────────────────────────────────────────────
    top = sort(collect(global_counts), by=last, rev=true)[1:min(20, length(global_counts))]
    println("\nTop 20 most frequent words:")
    println("$("Word"^18) Count")
    println("─" ^ 28)
    for (word, count) in top
        @printf "%-20s %7d\n" word count
    end
    println("\nTotal unique words: $(length(global_counts))\n")
end

function _count_file(path::AbstractString)::Dict{String,UInt64}
    counts = Dict{String,UInt64}()
    open(path, "r") do io
        for line in eachline(io)
            for m in eachmatch(r"\p{L}+", line)
                w = lowercase(m.match)
                counts[w] = get(counts, w, 0) + 1
            end
        end
    end
    return counts
end

# ── Entry point ─────────────────────────────────────────────────────────
if length(ARGS) < 1
    @warn "Usage: julia word_freq.jl <directory>"
    exit(1)
end
word_freq(ARGS[1])
