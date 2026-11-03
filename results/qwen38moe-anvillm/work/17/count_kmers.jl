"""
    count_kmers(seq::AbstractString, k::Integer) -> Dict{UInt64,Int}

Count every length-`k` substring (k-mer) of a DNA sequence `seq`.

Returns a `Dict{UInt64,Int}` mapping each encoded k-mer to its count.
Bases are encoded 2 bits each (`A=00, C=01, G=10, T=11`) into a `UInt64`
using a rolling update — no string slicing is performed.

`k` must be in `1:31` (2·31 = 62 bits fits in `UInt64`).
Any character outside `ACGT` (case-sensitive) throws `ArgumentError`.

    decode(code::UInt64, k::Integer) -> String

Decode the 2-bit encoding back to the original DNA string.

Target performance: ~10⁷ bases in ~1 second on a modern CPU.
"""

const _BASE_TABLE = Dict{UInt8,UInt8}(
    UInt8('A') => 0x00,
    UInt8('C') => 0x01,
    UInt8('G') => 0x02,
    UInt8('T') => 0x03,
)

function count_kmers(seq::AbstractString, k::Integer)
    if k < 1
        throw(DomainError(k, "k must be ≥ 1"))
    end
    if k > 31
        throw(DomainError(k, "k must be ≤ 31 (2·k ≤ 62 bits fits in UInt64)"))
    end

    mask = (UInt64(1) << (2k)) - UInt64(1)   # keep only the lowest 2k bits
    code = zero(UInt64)
    counts = Dict{UInt64,Int}()

    for i in 1:length(seq)
        b = UInt8(seq[i])
        val = get(_BASE_TABLE, b, nothing)
        val === nothing && throw(ArgumentError(
            "Invalid base at position $i: '$seq[i]' (only ACGT allowed)"
        ))

        code = ((code << 2) | val) & mask

        if i >= k
            count = get!(counts, code, 0)
            counts[code] = count + 1
        end
    end

    return counts
end

"""
    decode(code::UInt64, k::Integer) -> String

Decode a 2-bit encoded k-mer back to its DNA string.

    decode(UInt64(27), 4) == "ACGT"
"""
function decode(code::UInt64, k::Integer)
    k < 1 && throw(DomainError(k, "k must be ≥ 1"))
    k > 31 && throw(DomainError(k, "k must be ≤ 31"))

    chars = Vector{Char}(undef, k)
    for i in 0:k-1
        val = Int((code >> (2*(k - 1 - i))) & 0x3)
        chars[i + 1] = "ACGT"[val + 1]
    end
    return String(chars)
end

# ── Quick smoke test ──────────────────────────────────────────────────────────
if abspath(PROGRAM_FILE) == @__FILE__
    seq = "ACGTACGTACGT"
    k = 4
    counts = count_kmers(seq, k)

    println("k-mers in \"$seq\" (k=$k):")
    for (code, cnt) in sort(collect(counts), by=first)
        println("  $(decode(code, k)) → $cnt")
    end

    # Round-trip check: ACGT encodes to 27 (0b00011011)
    @assert decode(UInt64(27), k) == "ACGT"
    println("\nRound-trip OK ✓")
end
