"""
    count_kmers(seq, k)

Count all k-mers (substrings of length k) in a DNA sequence using a rolling
bit-packed hash. Each base is encoded as 2 bits (A=00, C=01, G=10, T=11) into
a UInt64 window. Supports k ≤ 31 (62 bits used).

Arguments:
  seq::AbstractString  - DNA sequence (upper or lowercase ACGT)
  k::Int               - k-mer length (1 ≤ k ≤ 31)

Returns:
  (counts, decode) where:
    counts::Dict{UInt64,Int} - map from k-mer hash to occurrence count
    decode(code::UInt64) -> String - reconstructs the k-mer string from its hash

Invalid characters throw ArgumentError.

Performance: O(n) time, O(4^k) worst-case space.
"""
function count_kmers(seq::AbstractString, k::Int)
    if k < 1 || k > 31
        throw(ArgumentError("k must be between 1 and 31, got $k"))
    end

    n = length(seq)
    if n < k
        throw(ArgumentError("sequence length $n < k=$k"))
    end

    # Inline base encoding for speed
    function encode_base(b)
        if b == 'A' || b == 'a'
            return 0
        elseif b == 'C' || b == 'c'
            return 1
        elseif b == 'G' || b == 'g'
            return 2
        elseif b == 'T' || b == 't'
            return 3
        else
            throw(ArgumentError("invalid DNA base '$b'"))
        end
    end

    # Build initial k-mer hash (leftmost base = most significant bits)
    hash = 0
    for i in 1:k
        hash = (hash << 2) | encode_base(seq[i])
    end

    counts = Dict{UInt64, Int}()
    counts[UInt64(hash)] = 1

    # Rolling window mask: keep only the last 2k bits
    mask = (UInt64(1) << (2 * k)) - 1

    # Slide window
    for i in (k + 1):n
        hash = ((hash << 2) | encode_base(seq[i])) & mask
        c = get(counts, UInt64(hash), 0)
        counts[UInt64(hash)] = c + 1
    end

    # Closure that captures k for decoding
    function decode(code::UInt64)
        bases = ('A', 'C', 'G', 'T')
        result = Vector{Char}(undef, k)
        for i in 0:(k - 1)
            idx = Int((code >> (2 * (k - 1 - i))) & 0b11)
            result[i + 1] = bases[idx + 1]
        end
        return String(result)
    end

    return (counts, decode)
end

# --- Demo / self-test ---
if abspath(PROGRAM_FILE) == @__FILE__
    # Small test
    seq = "ACGTACGTACGT"
    counts, decode = count_kmers(seq, 3)
    println("3-mers in \"ACGTACGTACGT\":")
    for (code, count) in sort(collect(counts), by = x -> decode(x[1]))
        println("  $(decode(code)): $count")
    end

    # Verify decode roundtrip
    for (code, _) in counts
        @assert decode(code) in ["ACG", "CGT", "GTA", "TAC"]
    end
    println("✓ decode roundtrip verified")

    # Performance test: 10^7 bases
    using Random
    Random.seed!(42)
    big_seq = join(rand(["A", "C", "G", "T"], 10_000_000))

    @time begin
        big_counts, _ = count_kmers(big_seq, 10)
    end
    println("✓ counted 10^7 bases, k=10, $(length(big_counts)) unique k-mers")
end
