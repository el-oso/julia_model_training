include("parse_csv_line.jl")
using Test

@testset "parse_csv_line" begin
    # Basic fields
    @test parse_csv_line("a,b,c") == ["a","b","c"]
    @test parse_csv_line("a,b,c,d") == ["a","b","c","d"]

    # Empty fields
    @test parse_csv_line(",") == ["",""]
    @test parse_csv_line(",b,") == ["","b",""]
    @test parse_csv_line(",,") == ["","",""]

    # Quoted fields
    @test parse_csv_line("\"a,b\",c") == ["a,b","c"]
    @test parse_csv_line("\"a\"\"b\",c") == ["a\"b","c"]
    @test parse_csv_line("\"a\"\"\"b\""; delim=',') == ["a\"", "b\""]
    @test parse_csv_line("\"\",a") == ["","a"]
    @test parse_csv_line("a,\"b\"") == ["a","b"]

    # Unterminated quote → throws
    @test_throws ErrorException parse_csv_line("\"unclosed")
    @test_throws ErrorException parse_csv_line("\"b")
    @test_throws ErrorException parse_csv_line("a,\"b")

    # Whitespace after closing quote (RFC 4180)
    @test parse_csv_line("\"a\", b") == ["a", " b"]

    # Empty quoted field
    @test parse_csv_line("\"\",a") == ["","a"]

    # Single field no delimiter
    @test parse_csv_line("hello") == ["hello"]

    # Quoted field with newlines (valid in RFC 4180)
    @test parse_csv_line("\"a\nb\",c") == ["a\nb","c"]

    # Trailing delimiter
    @test parse_csv_line("a,b,c,") == ["a","b","c",""]
    @test parse_csv_line("a,\"b\",") == ["a","b",""]

    # Custom delimiter
    @test parse_csv_line("a;b;c", delim=';') == ["a","b","c"]

    # Escaped quote at end of quoted field
    @test parse_csv_line("\"a\"\"\"") == ["a\""]

    # Empty line → one empty field
    @test parse_csv_line("") == [""]

    # Single quoted field
    @test parse_csv_line("\"hello\"") == ["hello"]
    @test parse_csv_line("\"\"") == [""]

    # Multiple escaped quotes
    @test parse_csv_line("\"a\"\"b\"\"c\"") == ["a\"b\"c"]

    # Trailing comma after quoted field → empty field
    @test parse_csv_line("\"a\",") == ["a", ""]
end

println("All correctness tests passed ✓")

function benchmark_short_lines()
    lines = [join(rand('a':'z', 5) for _ in 1:10) for _ in 1:1_000_000]
    for l in lines[1:100]
        parse_csv_line(l)
    end
    t = @elapsed for l in lines
        parse_csv_line(l)
    end
    println("10⁶ short 10-field lines: $(1_000_000/t) lines/s  (target ≥ 1e6)")
    println("  per line: $(t/1_000_000*1e6) μs")
end

function benchmark_mixed_quoting()
    lines = String[]
    for _ in 1:100_000
        field = rand() < 0.4 ? "\"" * "a,b,c" * "\"" : "a,b,c"
        push!(lines, field * ",d,e")
    end
    for l in lines[1:100]
        parse_csv_line(l)
    end
    t = @elapsed for l in lines
        parse_csv_line(l)
    end
    println("10⁵ mixed-quoted lines: $(100_000/t) lines/s")
end

function benchmark_unescaped_quotes()
    lines = ["\"a\"\"b\"\"c\"" for _ in 1:100_000]
    for l in lines[1:100]
        parse_csv_line(l)
    end
    t = @elapsed for l in lines
        parse_csv_line(l)
    end
    println("10⁵ lines with escaped quotes: $(100_000/t) lines/s")
end

benchmark_short_lines()
benchmark_mixed_quoting()
benchmark_unescaped_quotes()
