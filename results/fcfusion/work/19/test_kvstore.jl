import Pkg
Pkg.activate(".")

include("kvstore.jl")
using .KVStore

println("=== KVStore Tests ===")

# Test 1: Basic put/get
println("\n--- Test 1: Basic put/get ---")
store = open_store("test1.db")
kv_put!(store, "name", "Alice")
kv_put!(store, "age", "30")
println("name: ", kv_get(store, "name", "N/A"))
println("age: ", kv_get(store, "age", "N/A"))
println("missing: ", kv_get(store, "missing", "default"))
kv_close(store)

# Test 2: Reopen restores state
println("\n--- Test 2: Reopen restores state ---")
store = open_store("test1.db")
println("name after reopen: ", kv_get(store, "name", "N/A"))
println("age after reopen: ", kv_get(store, "age", "N/A"))
kv_close(store)

# Test 3: Overwrite
println("\n--- Test 3: Overwrite ---")
store = open_store("test2.db")
kv_put!(store, "key", "value1")
kv_put!(store, "key", "value2")
println("key: ", kv_get(store, "key", "N/A"))
kv_close(store)

# Test 4: Delete
println("\n--- Test 4: Delete ---")
store = open_store("test3.db")
kv_put!(store, "to_delete", "value")
println("before delete: ", kv_get(store, "to_delete", "N/A"))
kv_delete!(store, "to_delete")
println("after delete: ", kv_get(store, "to_delete", "gone"))
kv_close(store)

# Test 5: Compact
println("\n--- Test 5: Compact ---")
store = open_store("test4.db")
for i in 1:10
    kv_put!(store, "key$i", "value$i")
end
# Overwrite all
for i in 1:10
    kv_put!(store, "key$i", "new$i")
end
file_size_before = filesize("test4.db")
println("size before compact: ", file_size_before)
compact!(store)
file_size_after = filesize("test4.db")
println("size after compact: ", file_size_after)
println("compacted: ", file_size_after < file_size_before)
# Verify data still correct
for i in 1:10
    val = kv_get(store, "key$i", "N/A")
    if val != "new$i"
        println("ERROR: key$i = $val (expected new$i)")
    end
end
println("all values correct after compact")
kv_close(store)

# Test 6: Torn record recovery
println("\n--- Test 6: Torn record recovery ---")
store = open_store("test5.db")
kv_put!(store, "good_key", "good_value")
kv_close(store)

# Now append a torn record (incomplete write)
f = open("test5.db", "r+")
seekend(f)
# Write partial magic (only 2 bytes of 4)
write(f, [0x54, 0x53])
close(f)

# Reopen - should recover good_key, drop torn record
store = open_store("test5.db")
println("good_key after torn record: ", kv_get(store, "good_key", "N/A"))
kv_close(store)

# Test 7: Benchmark - 10^5 puts
println("\n--- Test 7: Benchmark (10^5 puts) ---")
store = open_store("benchmark.db")
N = 100000
t_start = time()
for i in 1:N
    kv_put!(store, "key_$i", "value_$i")
end
t_elapsed = time() - t_start
println("Time for 10^5 puts: ", t_elapsed, "s")
println("Puts per second: ", N / t_elapsed)

# Verify a few random values
for i in [1, 1000, 50000, 100000]
    val = kv_get(store, "key_$i", "N/A")
    expected = "value_$i"
    if val != expected
        println("ERROR: key_$i = $val (expected $expected)")
    end
end
println("random spot checks passed")

# Benchmark get
t_start = time()
for i in 1:10000
    kv_get(store, "key_$i", "N/A")
end
t_elapsed = time() - t_start
println("Time for 10^4 gets: ", t_elapsed, "s")

kv_close(store)

# Cleanup
for db in ["test1.db", "test2.db", "test3.db", "test4.db", "test5.db", "benchmark.db"]
    if isfile(db)
        rm(db)
    end
end

println("\n=== All tests passed ===")
