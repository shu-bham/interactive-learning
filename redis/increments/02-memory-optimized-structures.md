# Increment 02: The Memory Games (ZipLists, Intsets, and Listpacks)

In the previous lesson, we looked at SDS. Now, let's explore how Redis stores collections (Lists, Sets, Hashes) efficiently. As a Staff Engineer, you must understand **Memory Locality** and why Redis avoids pointers whenever possible for small datasets.

## 1. The Pointer Problem
Standard data structures like Doubly Linked Lists use pointers.
- A pointer on a 64-bit system is 8 bytes.
- A `listNode` might have `prev`, `next`, and `value` pointers (24 bytes just for metadata!).
- Pointers cause **CPU Cache Misses** because data is scattered across memory.

## 2. ZipLists: The Sequential Optimization (Legacy but Important)
For small lists/hashes, Redis uses a **ZipList**. A ZipList is a single contiguous block of memory.

### Structure:
`[zlbytes] [zltail] [zllen] [entry1] [entry2] ... [zlend]`

- **Pros**: Zero pointer overhead, excellent cache locality.
- **Cons**: `O(N)` for updates/deletes. If the list grows too large, shifting memory becomes expensive.
- **The "Cascading Update" problem**: If an entry grows, it might trigger a resize of all subsequent entries (fixed by `listpack`).

---

## 3. Intsets: The Ultimate Integer Set
When a Set contains only integers, Redis uses an **Intset**.

### Why?
Integers are stored in their smallest possible representation (16-bit, 32-bit, or 64-bit). If you add a 64-bit number to a 16-bit Intset, Redis **upgrades** the entire structure.

> [!NOTE]
> **Tech Jargon Refresher: Memory Locality**
> The principle that once a piece of memory is accessed, nearby memory locations are likely to be accessed soon. Contiguous structures (ZipLists) take advantage of CPU L1/L2 caches much better than pointer-based ones.

---

## 4. Modern Redis (v7.0+): Listpacks and Quicklists

In modern Redis, ZipLists are largely replaced by **Listpacks**.
- **Listpack**: Similar to ZipList but avoids the "Cascading Update" problem by not storing the previous entry's length in a way that affects subsequent offsets.
- **Quicklist**: A hybrid structure. It is a doubly linked list of Listpacks (or ZipLists). This gives you the `O(1)` head/tail performance of linked lists with the memory efficiency of ZipLists.

---

## 5. Hands-on Exercise: Tracking Encodings

Let's see these optimizations in action.

### Step 1: Small Hash (ZipList/Listpack)
Connect to your `redis-primary` and run:
```redis
HSET myhash field1 "value1" field2 "value2"
OBJECT ENCODING myhash
# Answer: "listpack" (in v7) or "ziplist" (in older versions)
```

### Step 2: Breaking the Limit
By default, once a Hash exceeds 512 entries or a field exceeds 64 bytes, it converts to a `hashtable`.
```redis
# Let's hit the string size limit
HSET myhash bigfield "A".repeat(100) # This is a pseudo-command, use a long string manually
# Or just run:
HSET myhash bigfield "this string is definitely longer than 64 bytes and will trigger a conversion to a real hash table"
OBJECT ENCODING myhash
# Answer: "hashtable"
```

### Step 3: Integer Sets
```redis
SADD myset 1 2 3 4 5
OBJECT ENCODING myset
# Answer: "intset"

SADD myset "hello"
OBJECT ENCODING myset
# Answer: "hashtable" (The moment a non-integer is added, it converts)
```

---

## Your Task
1. Verify the `OBJECT ENCODING` for a small Hash and a small Set.
2. Find the exact configuration parameters in `redis.conf` that control these thresholds (`hash-max-listpack-entries`, `set-max-intset-entries`).
3. Try to "break" an `intset` and observe the conversion.
4. Let me know when you are ready to discuss **The Dict (Hashtable) and Incremental Rehashing**.

---

## Solutions & Staff Level Insights

### Task 1: Verify Encodings
- **Hash**: Small hashes use `listpack` (or `ziplist` in pre-7.0).
- **Set**: Sets with only integers use `intset`.

### Task 2: Configuration Parameters
The default limits in a standard `redis.conf` (or internal defaults) are:
- `hash-max-listpack-entries 512`: Converts to `hashtable` if entry count > 512.
- `hash-max-listpack-value 64`: Converts to `hashtable` if any value size > 64 bytes.
- `set-max-intset-entries 512`: Converts to `hashtable` if set size > 512.

### Task 3: Breaking the Intset
**Experiment**:
```redis
SADD myset 1 2 3
OBJECT ENCODING myset  # -> intset
SADD myset "a"
OBJECT ENCODING myset  # -> hashtable
```
**Staff Level Insight**: Once a structure is "upgraded" (e.g., from `intset` to `hashtable` or `listpack` to `hashtable`), it **never automatically downgrades** even if you delete the large/non-integer elements. This prevents "thrashing" (repeatedly converting back and forth), which would be computationally expensive.
