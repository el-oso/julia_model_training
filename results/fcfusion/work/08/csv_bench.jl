include("csv_parser.jl")

using BenchmarkTools

# Benchmark with various line types
lines = [
    "a,b,c",
    "\"quoted,field\",normal",
    "field1,\"field\"\"with\"\"quotes\",field3",
    "café,naïve,müller",
    "a,,c",
    "\"\"",
]

for line in lines
    result = parse_csv_line(line)
    println("$line -> $result")
end

# Large-scale benchmark
println("\n--- Large-scale benchmark ---")
test_line = "a,b,c,d,e,f,g,h,i,j"
n_lines = 1_000_000

t0 = time()
for i in 1:n_lines
    parse_csv_line(test_line)
end
t1 = time()

elapsed = t1 - t0
println("Parsed $n_lines lines in $elapsed seconds")
println("Rate: $(n_lines / elapsed) lines/sec")
println("Per line: $(elapsed / n_lines * 1e9) ns")
