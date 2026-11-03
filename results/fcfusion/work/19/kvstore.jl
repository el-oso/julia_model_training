module KVStore

export open_store, kv_put!, kv_get, kv_delete!, compact!, kv_close

# CRC32 table (IEEE polynomial 0xEDB88320, bit-reversed)
let table = Vector{UInt32}(undef, 256)
    for i in 0:255
        crc = UInt32(i)
        for _ in 1:8
            if crc & 1 != 0
                crc = (crc >> 1) ⊻ 0xEDB88320
            else
                crc >>= 1
            end
        end
        table[i + 1] = crc
    end
    global CRC_TABLE = table
end

function crc32(data::Vector{UInt8})
    crc = UInt32(0xFFFFFFFF)
    for b in data
        idx = Int((crc ⊻ b) & 0xFF)
        crc = (crc >> 8) ⊻ CRC_TABLE[idx + 1]
    end
    return crc ⊻ UInt32(0xFFFFFFFF)
end

const MAGIC = 0x4B565354  # "KVST"
const FLAG_TOMBSTONE = 0x01

mutable struct KVStore
    path::String
    f::IO
    index::Dict{String, Int}
    closed::Bool
end

function open_store(path::String)
    if isfile(path)
        f = open(path, "r+")
    else
        f = open(path, "w+")
    end

    store = KVStore(path, f, Dict{String, Int}(), false)

    rebuild_index!(store)
    seekend(store.f)

    return store
end

function rebuild_index!(store::KVStore)
    store.index = Dict{String, Int}()

    seek(store.f, 0)
    file_size = filesize(store.path)

    while position(store.f) < file_size
        offset = position(store.f)

        # Read header: magic(4) + flags(1) + key_len(4) + val_len(4) = 13 bytes
        header = read(store.f, 13)
        if length(header) < 13
            break  # Incomplete header - torn record
        end

        # Parse magic
        magic = UInt32(header[1]) | (UInt32(header[2]) << 8) | (UInt32(header[3]) << 16) | (UInt32(header[4]) << 24)
        if magic != MAGIC
            break  # Not a valid record
        end

        flags = header[5]
        key_len = Int(UInt32(header[6]) | (UInt32(header[7]) << 8) | (UInt32(header[8]) << 16) | (UInt32(header[9]) << 24))
        val_len = Int(UInt32(header[10]) | (UInt32(header[11]) << 8) | (UInt32(header[12]) << 16) | (UInt32(header[13]) << 24))

        # Check if record fits in remaining file
        record_size = 13 + key_len + val_len + 4
        if file_size - offset < record_size
            break  # Torn record - not enough data
        end

        # Read entire record
        record = header
        key_data = read(store.f, key_len)
        val_data = read(store.f, val_len)
        crc_bytes = read(store.f, 4)

        # Compute CRC over header + key + value
        record_with_key_val = [record; key_data; val_data]
        computed_crc = crc32(record_with_key_val)

        stored_crc = UInt32(crc_bytes[1]) | (UInt32(crc_bytes[2]) << 8) | (UInt32(crc_bytes[3]) << 16) | (UInt32(crc_bytes[4]) << 24)

        if computed_crc != stored_crc
            break  # CRC mismatch - corrupted or torn record
        end

        key = String(key_data)
        if flags & FLAG_TOMBSTONE == 0
            store.index[key] = offset
        end
    end
end

function write_record!(store::KVStore, key::String, value::String, flags::UInt8)
    key_bytes = key
    val_bytes = value
    key_len = length(key_bytes)
    val_len = length(val_bytes)

    # Build record as a flat vector
    record = Vector{UInt8}(undef, 13 + key_len + val_len + 4)

    # Magic (4 bytes, little-endian)
    record[1] = UInt8(MAGIC & 0xFF)
    record[2] = UInt8((MAGIC >> 8) & 0xFF)
    record[3] = UInt8((MAGIC >> 16) & 0xFF)
    record[4] = UInt8((MAGIC >> 24) & 0xFF)
    # Flags (1 byte)
    record[5] = UInt8(flags)
    # Key length (4 bytes, little-endian)
    record[6] = UInt8(key_len & 0xFF)
    record[7] = UInt8((key_len >> 8) & 0xFF)
    record[8] = UInt8((key_len >> 16) & 0xFF)
    record[9] = UInt8((key_len >> 24) & 0xFF)
    # Value length (4 bytes, little-endian)
    record[10] = UInt8(val_len & 0xFF)
    record[11] = UInt8((val_len >> 8) & 0xFF)
    record[12] = UInt8((val_len >> 16) & 0xFF)
    record[13] = UInt8((val_len >> 24) & 0xFF)
    # Key
    copyto!(record, 14, key_bytes)
    # Value
    copyto!(record, 14 + key_len, val_bytes)

    # Compute CRC over header + key + value
    crc = crc32(record[1:(13 + key_len + val_len)])

    # Append CRC (4 bytes, little-endian)
    crc_offset = 14 + key_len + val_len
    record[crc_offset] = UInt8(crc & 0xFF)
    record[crc_offset + 1] = UInt8((crc >> 8) & 0xFF)
    record[crc_offset + 2] = UInt8((crc >> 16) & 0xFF)
    record[crc_offset + 3] = UInt8((crc >> 24) & 0xFF)

    offset = position(store.f)
    write(store.f, record)
    flush(store.f)

    return offset
end

function kv_put!(store::KVStore, key::String, value::String)
    offset = write_record!(store, key, value, 0x00)
    store.index[key] = offset
    return nothing
end

function kv_get(store::KVStore, key::String, default)
    if !haskey(store.index, key)
        return default
    end

    offset = store.index[key]
    seek(store.f, offset)

    # Read header
    header = read(store.f, 13)
    key_len = Int(UInt32(header[6]) | (UInt32(header[7]) << 8) | (UInt32(header[8]) << 16) | (UInt32(header[9]) << 24))
    val_len = Int(UInt32(header[10]) | (UInt32(header[11]) << 8) | (UInt32(header[12]) << 16) | (UInt32(header[13]) << 24))

    # Skip key, read value
    read(store.f, key_len)
    val_data = read(store.f, val_len)

    return String(val_data)
end

function kv_delete!(store::KVStore, key::String)
    write_record!(store, key, "", FLAG_TOMBSTONE)
    delete!(store.index, key)
    return nothing
end

function compact!(store::KVStore)
    tmp_path = store.path * ".tmp"

    tmp = open(tmp_path, "w+")
    try
        for (key, offset) in store.index
            seek(store.f, offset)
            header = read(store.f, 13)
            key_len = Int(UInt32(header[6]) | (UInt32(header[7]) << 8) | (UInt32(header[8]) << 16) | (UInt32(header[9]) << 24))
            val_len = Int(UInt32(header[10]) | (UInt32(header[11]) << 8) | (UInt32(header[12]) << 16) | (UInt32(header[13]) << 24))

            # Read key and value
            key_data = read(store.f, key_len)
            val_data = read(store.f, val_len)
            crc_data = read(store.f, 4)

            # Write entire record including header
            write(tmp, header)
            write(tmp, key_data)
            write(tmp, val_data)
            write(tmp, crc_data)
        end
        close(tmp)
    catch
        try
            close(tmp)
        catch
        end
        throw()
    end

    close(store.f)
    mv(tmp_path, store.path, force=true)

    # Reopen and rebuild index
    store.f = open(store.path, "r+")
    rebuild_index!(store)
    seekend(store.f)

    return nothing
end

function kv_close(store::KVStore)
    if !store.closed
        flush(store.f)
        close(store.f)
        store.closed = true
    end
    return nothing
end

end  # module
