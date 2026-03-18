# Increment 05: Near Real-Time Search

Elasticsearch is called "near real-time" (NRT) — documents aren't immediately searchable after indexing. This module explains why and how to tune it.

---

## 1. The Write Path Internals

When you index a document, here's what happens inside a shard:

```
1. Client sends document
         │
         ▼
2. Document written to TRANSLOG (append-only, fsync'd)
         │
         ▼
3. Document added to IN-MEMORY BUFFER
         │
         ▼
4. [After refresh_interval] Buffer → New Segment (searchable!)
         │
         ▼
5. [After flush] Translog cleared, segment fsync'd to disk
```

> [!NOTE]
> **Comparison to PostgreSQL WAL**: The translog is ES's equivalent of PostgreSQL's Write-Ahead Log. It ensures durability even if the process crashes before a segment is written to disk.

---

## 2. The Three Key Operations

| Operation | What it does | When it happens | Performance |
|-----------|--------------|-----------------|-------------|
| **Refresh** | Buffer → Segment (searchable) | Every 1s by default | Cheap |
| **Flush** | Translog → Disk, reset translog | When translog is large or on interval | Moderate |
| **Merge** | Combine segments, remove deletes | Background, by Lucene | Expensive |

---

## 3. Refresh: Making Documents Searchable

```bash
# Default: every 1 second
PUT /my-index/_settings
{
  "index": {
    "refresh_interval": "1s"
  }
}
```

During bulk indexing, you might want to **disable** refresh:
```bash
PUT /my-index/_settings
{
  "index": {
    "refresh_interval": "-1"
  }
}
```

Then manually refresh after bulk insert:
```bash
POST /my-index/_refresh
```

> [!TIP]
> **Staff Insight**: For high-throughput indexing (logs, events), set `refresh_interval: 30s` or higher. The 1s default is optimized for search-heavy workloads, not write-heavy.

---

## 4. Translog: Durability Guarantee

The translog ensures that even if ES crashes between refreshes, data isn't lost.

```yaml
# Translog settings
index.translog.durability: request    # fsync after each request (safe, slow)
index.translog.durability: async      # fsync every 5s (faster, risk of 5s data loss)

index.translog.sync_interval: 5s      # For async mode
index.translog.flush_threshold_size: 512mb  # Flush when translog hits this size
```

> [!WARNING]
> **Staff Insight**: `async` translog is faster but risks losing the last 5s of data on crash. For critical data, use `request`. For logs/metrics where losing a few seconds is acceptable, `async` improves throughput significantly.

---

## 5. Flush: Committing to Disk

A flush:
1. Creates a new Lucene commit point
2. Fsyncs all segments to disk
3. Clears the translog

```bash
# Manual flush
POST /my-index/_flush

# Flush with synced marker (for snapshots)
POST /my-index/_flush/synced
```

You rarely need to manually flush — ES handles it automatically.

---

## 6. Refresh vs Flush vs Merge

```
Timeline of a shard:

|---INDEX---|---INDEX---|---INDEX---|---REFRESH---|---INDEX---|---FLUSH---|

         In-memory buffer builds up
                                     ↓
                              New segment created (searchable)
                                                              ↓
                                                      Disk-safe, translog cleared

Meanwhile, in the background:
[--Merge small segments into larger ones--]
```

---

## 7. Hands-on: Observing NRT Behavior

### Step 1: Create a test index with slow refresh
```bash
curl -X PUT "http://localhost:9200/nrt-test" -H "Content-Type: application/json" -d '
{
  "settings": {
    "number_of_shards": 1,
    "number_of_replicas": 0,
    "refresh_interval": "30s"
  }
}'
```

### Step 2: Index a document and try to search immediately
```bash
# Index
curl -X POST "http://localhost:9200/nrt-test/_doc" -H "Content-Type: application/json" -d '
{"message": "hello world", "timestamp": "2024-01-15T10:00:00Z"}'

# Search immediately
curl -s "http://localhost:9200/nrt-test/_search" | jq '.hits.total.value'
# Result: 0 (not searchable yet!)
```

### Step 3: Force refresh and search again
```bash
curl -X POST "http://localhost:9200/nrt-test/_refresh"

curl -s "http://localhost:9200/nrt-test/_search" | jq '.hits.total.value'
# Result: 1 (now searchable!)
```

### Step 4: Use refresh=true for immediate visibility
```bash
curl -X POST "http://localhost:9200/nrt-test/_doc?refresh=true" -H "Content-Type: application/json" -d '
{"message": "immediately visible", "timestamp": "2024-01-15T10:01:00Z"}'

curl -s "http://localhost:9200/nrt-test/_search" | jq '.hits.total.value'
# Result: 2 (immediately visible!)
```

### Step 5: Observe translog
```bash
curl -X GET "http://localhost:9200/nrt-test/_stats/translog?pretty"
```

Look at `uncommitted_operations` and `uncommitted_size_in_bytes`.

### Step 6: Flush and check again
```bash
curl -X POST "http://localhost:9200/nrt-test/_flush"
curl -X GET "http://localhost:9200/nrt-test/_stats/translog?pretty"
```

After flush, `uncommitted_operations` should be 0.

---

## 8. Segment Behavior

```bash
# See current segments
curl -X GET "http://localhost:9200/nrt-test/_segments?pretty"
```

Each refresh creates a new segment. Too many small segments = slow searches.

### Force merge (compact segments)
```bash
curl -X POST "http://localhost:9200/nrt-test/_forcemerge?max_num_segments=1"
curl -X GET "http://localhost:9200/nrt-test/_segments?pretty"
```

> [!WARNING]
> **Staff Insight**: Force merge is resource-intensive and blocks indexing on that shard. Only use on read-only indices (e.g., yesterday's logs). Never on active indices.

---

## 9. Tuning for Different Workloads

### Write-heavy (logs, metrics)
```json
{
  "settings": {
    "refresh_interval": "30s",
    "translog.durability": "async",
    "translog.sync_interval": "5s"
  }
}
```

### Search-heavy (e-commerce, real-time)
```json
{
  "settings": {
    "refresh_interval": "1s",
    "translog.durability": "request"
  }
}
```

### Bulk reindexing
```json
{
  "settings": {
    "refresh_interval": "-1",
    "number_of_replicas": 0
  }
}
```
After reindex, set back to normal values.

---

## Your Task

1. **Measure refresh cost**: Index 10,000 documents with `refresh_interval: 1s` vs `refresh_interval: -1` (manual refresh at end). Compare total time.

2. **Translog experiment**: Set `translog.durability: async`. Index 100 documents. Kill the ES container immediately (`docker kill`). Restart. How many documents survived?

3. **Segment analysis**: Index 50 documents one at a time with `refresh=true` between each. Count segments. Force merge. Count again.

---

## Solutions & Staff Level Insights

### Task 1: Refresh overhead
With 1s refresh, you'll see I/O spikes every second and potentially slower indexing. With disabled refresh, bulk indexing is 2-5x faster (no segment creation overhead during indexing).

### Task 2: Translog durability
With `async`, you might lose documents indexed in the last 5 seconds before the kill. With `request`, all acknowledged documents survive.

### Task 3: Segment explosion
You'll see ~50 segments (one per refresh). After force merge: 1 segment. This demonstrates why frequent refreshes create overhead.
