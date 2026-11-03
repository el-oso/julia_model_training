using Random, BenchmarkTools
include("count_kmers.jl")

Random.seed!(42)
dna = String(rand(['A','C','G','T'], 10_000_000))

println("Benchmark: 10⁷ random bases, k=31")
@btime count_kmers($dna, 31)

println("\nBenchmark: 10⁷ random bases, k=15")
@btime count_kmers($dna, 15)

println("\nBenchmark: 10⁷ random bases, k=6")
@btime count_kmers($dna, 6)

println("\ndistinct k-mers (k=31): ", length(count_kmers(dna, 31)))
println("distinct k-mers (k=15): ", length(count_kmers(dna, 15)))
println("distinct k-mers (k=6):  ", length(count_kmers(dna, 6)))

# Verify decode round-trip
counts = count_kmers(dna, 31)
for (code, cnt) in Iterators.take(counts, 3)
    s = decode(code, 31)
    @assert length(s) == 31
    @assert all(c -> c in "ACGT", s)
    println("  $(s[1:20])… → $cnt")
end

# Test error handling
try
    count_kmers("ACGT N ACGT", 3)
    println("ERROR: should have thrown")
catch e
    println("\nInvalid char error: ", typeof(e), " — ", e.msg)
end

try
    count_kmers("acgtacgt", 3)
    println("ERROR: lowercase should have thrown")
catch e
    println("Lowercase error: ", typeof(e), " — ", e.msg)
end
