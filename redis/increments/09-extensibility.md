# Increment 09: Extensibility (Lua Scripting & Redis Modules)

The final piece of the Staff-level puzzle is knowing how to extend Redis beyond its built-in data types and commands. This is often the difference between a complex application-side coordination layer and a clean, atomic Redis-side solution.

---

## 1. Lua Scripting: Server-Side Atomicity

Redis supports Lua scripts through the `EVAL` command.

### Why use Lua?
1. **Atomicity**: A script is executed as a single unit. No other script or command will run while it is executing. This is perfect for complex "check-and-set" logic.
2. **Efficiency**: Reduce network round-trips by sending a single script instead of multiple `GET` and `SET` commands.

### Modern Redis (v7.0+): Redis Functions
Before Redis 7, you had to manage script hashes (`EVALSHA`). Now, you can use **Redis Functions**, which are basically persistent Lua scripts stored on the server and replicated to slaves.

---

## 2. Redis Modules: The C Extensions

While Lua is great, it's still interpreted. If you need near-native performance or entirely new data structures (like Bloom Filters, Time Series, or Full-Text Search), you use **Redis Modules**.

- Written in C/C++/Rust.
- Loaded into Redis during startup or via `MODULE LOAD`.
- **Staff Insight**: Modules have access to the internal C APIs of Redis, including the `Dict` and `SDS` structures we learned in Module 1.

---

## 3. Hands-on Exercise: Atomic Logic

### Step 1: Solving a Race Condition with Lua
Let's try a logic: "Increment a counter only if it won't exceed 100."
```redis
# Try this EVAL in redis-cli
EVAL "local current = redis.call('GET', KEYS[1]) or 0; if tonumber(current) < 100 then return redis.call('INCR', KEYS[1]) else return current end" 1 mycounter
```

### Step 2: Exploring Loaded Modules
Check if any modules are loaded in your instance:
```redis
MODULE LIST
```
*(In the standard Alpine image, this will likely be empty, but it's the command you'd use in production environments like Redis Cloud or ElastiCache).*

---

## Your Task
1. Write a Lua script that deletes all keys matching a specific pattern (e.g., `repl_s_*`) using `redis.call('KEYS', ...)` and `redis.call('DEL', ...)`.
2. **Staff Question**: Why is the script you just wrote in Task 1 potentially dangerous for a production cluster with 10 million keys? (Hint: Module 0 - `UNLINK` and Lesson 01 - Reactor Pattern).
3. Research **Redlock**. How does Lua scripting play a role in implementing a distributed lock using Redlock?

---

## Solutions & Staff Level Insights

### Task 2: The "KEYS" Trap
**The Danger**: `KEYS` is an $O(N)$ operation that blocks the single thread. If you run it on 10 million keys, the script will lock the entire Redis instance for seconds.
- **Staff Solution**: Use `SCAN` in a loop inside the application, or use the `unlink` command inside the script if the key count is small.

### Task 3: Redlock
Lua is used in Redlock to ensure that a lock is only released by the client that owns it. The release script:
```lua
if redis.call("get",KEYS[1]) == ARGV[1] then
    return redis.call("del",KEYS[1])
else
    return 0
end
```
Without Lua, a client could accidentally delete a lock that has timed out and been acquired by another client (a "Check-and-Delete" race condition).
