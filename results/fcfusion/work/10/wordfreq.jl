#!/usr/bin/env julia
# Parallel word frequency counter
# Usage: julia wordfreq.jl <directory>
#
# Strategy: Each thread processes a subset of files and returns its own
# local Dict{String,Int}. The main thread merges the per-thread results
# sequentially. No shared mutable state is mutated concurrently, so the
# merge is race-free.

using Unicode

function count_words_in_file(path::String)::Dict{String, Int}
    text = read(path, String)
    counts = Dict{String, Int}()
    for m in eachmatch(r"[[:alpha:]]+", text)
        w = lowercase(m.match)
        counts[w] = get(counts, w, 0) + 1
    end
    return counts
end

function merge_counts(dicts::Vector{Dict{String, Int}})::Dict{String, Int}
    merged = Dict{String, Int}()
    for d in dicts
        for (w, c) in d
            merged[w] = get(merged, w, 0) + c
        end
    end
    return merged
end

if length(ARGS) < 1
    println("Usage: julia wordfreq.jl <directory>")
    exit(1)
end

dir = ARGS[1]
files = filter(f -> endswith(f, ".txt"), readdir(dir, join=true))
nfiles = length(files)
println("Processing $nfiles .txt files with $(Threads.nthreads()) threads...")

if nfiles == 0
    println("No .txt files found.")
    exit(0)
end

# Partition files across threads
nt = Threads.nthreads()
partition_size = cld(nfiles, nt)
partitions = []
for i in 0:nt-1
    start_idx = i * partition_size + 1
    end_idx = min((i + 1) * partition_size, nfiles)
    if start_idx > nfiles
        break
    end
    push!(partitions, files[start_idx:end_idx])
end

# Spawn one task per partition
tasks = []
for part in partitions
    t = Threads.@spawn begin
        local_counts = Dict{String, Int}()
        for f in part
            try
                file_counts = count_words_in_file(f)
                for (w, c) in file_counts
                    local_counts[w] = get(local_counts, w, 0) + c
                end
            catch e
                println("Error processing $f: $e")
            end
        end
        return local_counts
    end
    push!(tasks, t)
end

# Collect results (fetch blocks until each task is done)
results = [fetch(t) for t in tasks]

# Merge on main thread — race-free because no task is still running
merged = merge_counts(results)

# Print top 20
top = sort(collect(merged), by=p -> p[2], rev=true)[1:min(20, length(merged))]
println("\nTop 20 words:")
for (w, c) in top
    println("$c\t$w")
end
