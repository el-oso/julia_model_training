module AppendStore

    using CRC32c
    import Base.close
    import Base.get

    # ─── Constants ───────────────────────────────────────────────────────────────────

    const MAGIC = UInt8[0x4B, 0x56, 0x53, 0x54]   # "KVST"
    const MAGIC_LEN = 4
    const CRC_LEN = 4
    const HEADER_LEN = MAGIC_LEN + 4 + 4           # magic + key_len + val_len (fixed)
    const MIN_RECORD_LEN = HEADER_LEN + CRC_LEN      # empty key + empty value

    # ─── Internal state ──────────────────────────────────────────────────────────────

    mutable struct Store
        path::String
        io::IO
        # offset → (key, val_len) for every committed record
        # key is stored as a Vector{UInt8} for fast comparison
        index::Dict{String, Int64}
        # map key bytes → offset (avoids repeated allocations during replay)
        key_bytes::Dict{Vector{UInt8}, Int64}
        # current write position (file length)
        pos::Int64
        closed::Bool
    end

    # ─── Helpers ─────────────────────────────────────────────────────────────────────

    function _write_record(io::IO, key::Vector{UInt8}, val::Vector{UInt8})
        klen = length(key)
        vlen = length(val)

        # Write magic
        write(io, MAGIC)
        # Write key_len
        write(io, klen)
        # Write key
        write(io, key)
        # Write val_len
        write(io, vlen)
        # Write value
        write(io, val)
        # Write CRC32 over bytes 4..end (everything after magic)
        crc = crc32c(vcat(key, vlen, val))
        return write(io, crc)
    end

    function _read_record(io::IO)
        try
            # Read magic
            magic = read(io, MAGIC_LEN)
            magic == MAGIC || return nothing  # not a valid record

            # Read key_len (little-endian uint32)
            klen_bytes = read(io, 4)
            klen = UInt32(klen_bytes[1]) | (UInt32(klen_bytes[2]) << 8) | (UInt32(klen_bytes[3]) << 16) | (UInt32(klen_bytes[4]) << 24)
            # Read key
            key = read(io, klen)
            # Read val_len (little-endian uint32)
            vlen_bytes = read(io, 4)
            vlen = UInt32(vlen_bytes[1]) | (UInt32(vlen_bytes[2]) << 8) | (UInt32(vlen_bytes[3]) << 16) | (UInt32(vlen_bytes[4]) << 24)
            # Read value
            val = read(io, vlen)
            # Read CRC (little-endian uint32)
            crc_bytes = read(io, 4)
            crc = UInt32(crc_bytes[1]) | (UInt32(crc_bytes[2]) << 8) | (UInt32(crc_bytes[3]) << 16) | (UInt32(crc_bytes[4]) << 24)

            # Verify CRC over body: key_len(4) + key + val_len(4) + val
            body = IOBuffer()
            write(body, klen_bytes)  # key_len as 4 bytes
            write(body, key)
            write(body, vlen_bytes)  # val_len as 4 bytes
            write(body, val)
            stored = crc
            computed = crc32c(take!(body))
            stored == computed || return nothing  # torn record → drop
            return (key, val)
        catch
            return nothing  # partial read → torn record
        end
    end

    # ─── Public API ──────────────────────────────────────────────────────────────────

    """
        open_store(path::AbstractString) -> Store

    Open (or create) an append-only key-value store at `path`.
    Replays the log to build the in-memory index. A torn final record (crash mid-write)
    is silently dropped during replay.
    """
    function open_store(path::AbstractString)
        io = open(path, "a+")
        seek(io, 0)  # seek to beginning for replay
        index = Dict{String, Int64}()
        key_bytes = Dict{Vector{UInt8}, Int64}()

        # Replay: read records from the beginning, keep last seen per key
        pos = 0
        while !eof(io)
            pos = position(io)
            result = _read_record(io)
            if result === nothing
                # Torn record at end of file — truncate it away
                truncate(io, pos)
                break
            end
            key, val = result
            vlen = length(val)
            index[String(key)] = pos
            key_bytes[key] = pos
        end

        pos = position(io)
        return Store(path, io, index, key_bytes, pos, false)
    end

    """
        put!(store::Store, key::String, value::String) -> store

    Append a new record to the log (never overwrites; the *latest* put wins on get).
    """
    function put!(store::Store, key::String, value::String)
        store.closed && throw(ArgumentError("store is closed"))
        key_vec = Vector{UInt8}(key)
        val_vec = Vector{UInt8}(value)

        # Write the record
        seek(store.io, store.pos)
        write(store.io, MAGIC)
        write(store.io, UInt32(length(key_vec)))
        write(store.io, key_vec)
        write(store.io, UInt32(length(val_vec)))
        write(store.io, val_vec)
        # CRC over body: key_len(4) + key + val_len(4) + val
        body = IOBuffer()
        write(body, UInt32(length(key_vec)))
        write(body, key_vec)
        write(body, UInt32(length(val_vec)))
        write(body, val_vec)
        crc = crc32c(take!(body))
        write(store.io, crc)
        store.pos = position(store.io)

        # Update index: new offset wins
        store.index[key] = store.pos
        store.key_bytes[key_vec] = store.pos

        return store
    end

    """
        get(store::Store, key::String, default) -> value or default

    Return the value associated with `key`, or `default` if not found.
    Only reads the one record from disk.
    A tombstone (empty value) also returns `default`.
    """
    function get(store::Store, key::String, default)
        store.closed && throw(ArgumentError("store is closed"))
        pos = get(store.index, key, -1)
        pos == -1 && return default

        seek(store.io, pos)
        result = _read_record(store.io)
        result === nothing && return default   # safety: shouldn't happen
        _, val = result
        isempty(val) && return default          # tombstone → deleted
        return String(val)
    end

    """
        delete!(store::Store, key::String) -> store

    Mark a key as deleted by writing a tombstone (empty value).
    `get` will return `nothing` (or your chosen default) for this key.
    """
    function delete!(store::Store, key::String)
        store.closed && throw(ArgumentError("store is closed"))
        key_vec = Vector{UInt8}(key)

        # Write tombstone (empty value)
        seek(store.io, store.pos)
        write(store.io, MAGIC)
        write(store.io, UInt32(length(key_vec)))
        write(store.io, key_vec)
        write(store.io, UInt32(0))
        body = IOBuffer()
        write(body, UInt32(length(key_vec)))
        write(body, key_vec)
        write(body, UInt32(0))
        crc = crc32c(take!(body))
        write(store.io, crc)
        store.pos = position(store.io)

        # Update index: tombstone wins
        store.index[key] = store.pos
        store.key_bytes[key_vec] = store.pos

        return store
    end

    """
        compact!(store::Store) -> nothing

    Rewrite the log: only the latest value per key is kept.
    Eliminates all historical writes and tombstones.
    """
    function compact!(store::Store)
        store.closed && throw(ArgumentError("store is closed"))

        # Close current file
        close(store.io)

        # Read all valid records into memory first (before truncating)
        records = Vector{Tuple{Vector{UInt8}, Vector{UInt8}}}()
        io = open(store.path, "r")
        while !eof(io)
            result = _read_record(io)
            result === nothing && break
            push!(records, result)
        end
        close(io)

        # Truncate and rewrite
        new_io = open(store.path, "w")
        new_pos = 0

        for (key_bytes, val) in records
            write(new_io, MAGIC)
            write(new_io, UInt32(length(key_bytes)))
            write(new_io, key_bytes)
            write(new_io, UInt32(length(val)))
            write(new_io, val)
            body = IOBuffer()
            write(body, UInt32(length(key_bytes)))
            write(body, key_bytes)
            write(body, UInt32(length(val)))
            write(body, val)
            crc = crc32c(take!(body))
            write(new_io, crc)
            new_pos = position(new_io)
        end

        close(new_io)

        # Rebuild index from scratch
        index = Dict{String, Int64}()
        key_bytes_map = Dict{Vector{UInt8}, Int64}()

        io = open(store.path, "r")
        while !eof(io)
            pos = position(io)
            result = _read_record(io)
            result === nothing && break
            key, val = result
            index[String(key)] = pos
            key_bytes_map[key] = pos
        end
        close(io)

        store.index = index
        store.key_bytes = key_bytes_map
        store.pos = new_pos

        # Open fresh write handle
        store.io = open(store.path, "a+")
        return nothing
    end

    """
        close(store::Store) -> nothing

    Flush and close the underlying file.
    """
    function close(store::Store)
        store.closed && return
        flush(store.io)
        close(store.io)
        store.closed = true
        return nothing
    end

end  # module

# ─── Standalone benchmark (outside module) ───────────────────────────────────────

using BenchmarkTools

function _benchmark()
    tmp = tempname()
    s = AppendStore.open_store(tmp)

    @time begin
        for i in 1:100_000
            AppendStore.put!(s, "key_$(lpad(i, 6, '0'))", "value_$(lpad(i, 6, '0'))")
        end
        AppendStore.close(s)
    end

    # Verify round-trip
    s2 = AppendStore.open_store(tmp)
    @assert AppendStore.get(s2, "key_000001", "MISS") == "value_000001"
    @assert AppendStore.get(s2, "key_100000", "MISS") == "value_100000"
    @assert AppendStore.get(s2, "nonexistent", "MISS") == "MISS"
    AppendStore.close(s2)
    rm(tmp)

    return println("All assertions passed ✓")
end

# _benchmark()
