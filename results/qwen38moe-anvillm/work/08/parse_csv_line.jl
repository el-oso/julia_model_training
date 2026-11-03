"""
    parse_csv_line(line::AbstractString; delim=',') -> Vector{String}

Parse a single CSV line per RFC 4180. Quoted fields start and end with `"`
and may contain the delimiter; `""` inside a quoted field is a literal `"`.
An unterminated quoted field throws `ErrorException`.

Operates on `codeunits` (UInt8) for the scanning phase — all special
characters (delimiter, `"`, whitespace) are ASCII (single UTF-8 byte),
so byte-position tracking is valid. Final field extraction uses the
original `AbstractString` for correct UTF-8 handling.

Target: ≥ 10⁶ short lines / s.
"""
function parse_csv_line(line::AbstractString; delim=',')
    cu = codeunits(line)        # CodeUnits{UInt8, String} — fast UInt8 indexing
    n = length(cu)
    D = UInt8(delim)
    fields = String[]
    i = 1

    last_was_delimiter = false  # track for trailing-empty-field detection

    while i ≤ n
        if cu[i] == 0x22  # '"' — start of quoted field
            # Scan content after opening quote, correctly handling ""
            # Escaped "" pairs are skipped (advance by 2);
            # a standalone " (not followed by ") is the closing quote.
            j = i + 1
            while true
                if j > n
                    throw(ErrorException("unterminated quote"))
                elseif cu[j] != 0x22
                    j += 1
                elseif j == n
                    break  # last char is closing quote
                elseif cu[j+1] != 0x22
                    break  # standalone " is closing quote
                elseif j + 1 == n
                    break  # "" at end: second " is closing quote
                else
                    j += 2  # "" pair = escaped quote, skip both
                end
            end
            # j now points to the closing `"`
            push!(fields, _unescape(line, cu, i + 1, j - 1))
            last_was_delimiter = false

            # Advance past closing `"` and skip RFC 4180 trailing whitespace
            i = j + 1
            while i ≤ n && cu[i] ∈ (0x20, 0x09, 0x0A, 0x0D)
                i += 1
            end
            # Skip delimiter immediately after closing quote
            # (it separates the quoted field from the next field,
            # not a new empty field)
            if i ≤ n && cu[i] == D
                i += 1
                last_was_delimiter = true
            end

        else
            # Unquoted field: scan to delimiter or end of line
            j = i
            while j ≤ n && cu[j] != D
                j += 1
            end
            last_was_delimiter = (j ≤ n)
            _push!(fields, line, cu, i, j > n ? n : j - 1)
            i = j + 1  # skip past delimiter (or past end)
        end
    end

    # Push the final remaining field
    if last_was_delimiter || i ≤ n || (n == 0)
        if i > n
            push!(fields, "")
        else
            _push!(fields, line, cu, i, n)
        end
    end

    return fields
end

# ── helpers ────────────────────────────────────────────────────────────────────

# Unquoted field: extract correct UTF-8 substring from the original string.
@inline function _push!(fields::Vector{String}, line::AbstractString,
                        ::Any, start::Int, stop::Int)
    if start > stop
        push!(fields, "")
    else
        push!(fields, line[start:stop])
    end
end

# Quoted field: unescape `""` → `"` inside the raw byte range.
# Fast path: no escaped quotes → return raw.
# Slow path: literal string replacement (not regex).
@inline function _unescape(line::AbstractString, cu::AbstractVector{UInt8},
                           start::Int, stop::Int)
    raw = line[start:stop]
    if !occursin("\"\"", raw)
        return raw
    end
    replace(raw, "\"\"" => "\"")
end
