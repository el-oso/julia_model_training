function parse_csv_line(line::AbstractString; delim=',')::Vector{String}
    fields = String[]
    field_bytes = UInt8[]
    in_quotes = false
    cu = codeunits(line)
    n = length(cu)
    delim_cu = UInt8(delim)
    quote_cu = UInt8('"')

    i = 1
    while i <= n
        c = cu[i]
        if in_quotes
            if c == quote_cu
                if i < n && cu[i + 1] == quote_cu
                    # Escaped quote: "" -> "
                    push!(field_bytes, quote_cu)
                    i += 2
                    continue
                else
                    # End of quoted field
                    in_quotes = false
                end
            else
                push!(field_bytes, c)
            end
        else
            if c == quote_cu
                in_quotes = true
            elseif c == delim_cu
                # End of field
                push!(fields, String(field_bytes))
                empty!(field_bytes)
            else
                push!(field_bytes, c)
            end
        end
        i += 1
    end

    if in_quotes
        throw(ErrorException("Unterminated quoted field"))
    end

    push!(fields, String(field_bytes))
    return fields
end

# Tests
@assert parse_csv_line("a,b,c") == ["a", "b", "c"]
@assert parse_csv_line("") == [""]
@assert parse_csv_line("a") == ["a"]
@assert parse_csv_line(",,") == ["", "", ""]
@assert parse_csv_line("\"a,b\",c") == ["a,b", "c"]
@assert parse_csv_line("a,\"b\"\"c\",d") == ["a", "b\"c", "d"]
@assert parse_csv_line("\"hello world\"") == ["hello world"]
@assert parse_csv_line("\"\"") == [""]
@assert parse_csv_line("a,\"b,c,d\",e") == ["a", "b,c,d", "e"]

# UTF-8
@assert parse_csv_line("café,naïve") == ["café", "naïve"]
@assert parse_csv_line("\"café,naïve\"") == ["café,naïve"]

# Custom delimiter
@assert parse_csv_line("a;b;c"; delim=';') == ["a", "b", "c"]

# Unterminated quote throws
try
    parse_csv_line("\"unterminated")
    @assert false "Should have thrown"
catch e
    @assert occursin("Unterminated", string(e))
end

println("All tests passed.")

# Benchmark
using BenchmarkTools

big_line = join(["field$i" for i in 1:10], ",")
println(@benchmark parse_csv_line(big_line) samples=1000)
