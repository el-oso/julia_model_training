#!/usr/bin/env julia
# julia --project=eval eval/compare.jl a.jsonl b.jsonl [...]
# Prints per-area pass rates side by side, one column per results file.
using JSON

length(ARGS) >= 2 || error("usage: compare.jl results_a.jsonl results_b.jsonl [...]")
load(f) = [JSON.parse(l) for l in eachline(f) if !isempty(strip(l))]
data = [load(f) for f in ARGS]
names = [splitext(basename(f))[1] for f in ARGS]
areas = sort(unique(r["area"] for d in data for r in d))
w = max(12, maximum(length, names) + 2)

println(rpad("area", 20), join(lpad.(names, w)))
function rate(d, a)
    rs = isnothing(a) ? d : filter(r -> r["area"] == a, d)
    isempty(rs) && return "-"
    p = count(r -> r["passed"], rs)
    return string(p, "/", length(rs), " ", round(Int, 100p / length(rs)), "%")
end
for a in areas
    println(rpad(a, 20), join(lpad(rate(d, a), w) for d in data))
end
println(rpad("ALL", 20), join(lpad(rate(d, nothing), w) for d in data))

# Tasks on which the first and last files disagree.
ids(d) = Dict(r["id"] => r["passed"] for r in d)
first_, last_ = ids(data[1]), ids(data[end])
common = sort(collect(intersect(keys(first_), keys(last_))))
gained = [i for i in common if !first_[i] && last_[i]]
lost = [i for i in common if first_[i] && !last_[i]]
println("\nfixed in $(names[end]) (failed in $(names[1])): ", isempty(gained) ? "-" : join(gained, ", "))
println("regressed in $(names[end]): ", isempty(lost) ? "-" : join(lost, ", "))
