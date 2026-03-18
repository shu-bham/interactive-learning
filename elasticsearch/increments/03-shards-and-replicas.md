# Increment 03: Shards & Replicas

This is where Elasticsearch's horizontal scaling story begins. Understanding sharding is critical for designing indices that scale.

---

## 1. What is a Shard?

A **shard** is a single Lucene index. When you create an ES index, you're actually creating a collection of shards.

```
ES Index "products"
├── Primary Shard 0 (Lucene index)
├── Primary Shard 1 (Lucene index)
└── Primary Shard 2 (Lucene index)
```

**Key insight**: Elasticsearch is a coordinator on top of many Lucene instances.

> [!NOTE]
> **Comparison to PostgreSQL**: Think of shards like table partitions (e.g., `products_2024_01`, `products_2024_02`), except ES handles routing automatically and can distribute partitions across nodes.

---

## 2. Primary vs Replica Shards

| Shard Type | Purpose | Writes | Reads |
|------------|---------|--------|-------|
| Primary | Source of truth | ✅ Receives writes first | ✅ Yes |
| Replica | Redundancy + read scaling | ❌ Receives writes from primary | ✅ Yes |

```
Node 1                   Node 2                   Node 3
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│ Primary 0       │     │ Primary 1       │     │ Primary 2       │
│ Replica 1       │     │ Replica 2       │     │ Replica 0       │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

Note: A replica is never on the same node as its primary (for fault tolerance).

---

## 3. The Write Path

When you index a document:

```
Client
   │
   ▼
Coordinating Node (any node can coordinate)
   │
   │ 1. Hash document ID → shard number
   │    shard = hash(_id) % number_of_primary_shards
   │
   ▼
Primary Shard (on some node)
   │
   │ 2. Index document locally
   │ 3. Forward to replica shards (in parallel)
   │
   ▼
Replica Shards
   │
   │ 4. Acknowledge to primary
   │
   ▼
Primary Shard
   │
   │ 5. Acknowledge to coordinating node
   │
   ▼
Client (success!)
```

> [!IMPORTANT]
> **Staff Insight**: By default, a write is acknowledged when the primary AND all in-sync replicas have indexed the document. This is controlled by `wait_for_active_shards`. Setting it to `1` (primary only) is faster but risks data loss if the primary dies before replication.

---

## 4. The Read Path

Searches are distributed across shards:

```
Client
   │
   ▼
Coordinating Node
   │
   │ Scatter (to all shards)
   │
   ├─────────────────┬─────────────────┐
   ▼                 ▼                 ▼
Shard 0           Shard 1           Shard 2
(or replica)      (or replica)      (or replica)
   │                 │                 │
   │ Local search    │ Local search    │ Local search
   │                 │                 │
   ├─────────────────┴─────────────────┘
   │
   ▼
Coordinating Node
   │
   │ Gather & merge results
   │
   ▼
Client (final results)
```

**Key Points**:
- The coordinating node picks either primary OR replica for each shard (load balancing)
- More replicas = more read throughput
- Each shard searches its local Lucene index

---

## 5. Shard Sizing: The Critical Decision

You **cannot change the number of primary shards** after index creation!

### Oversharding (Too Many Shards)
```
Index with 100 shards, 1 million docs
= 10,000 docs per shard
```
- Each shard has overhead (memory for segment metadata, thread pools)
- Searches must query 100 shards and merge — high coordination cost
- Cluster state bloat

### Undersharding (Too Few Shards)
```
Index with 1 shard, 1 billion docs
= Huge Lucene index that can't be distributed
```
- Can't scale horizontally
- Single node must hold all data
- Long segment merges

### The Sweet Spot (Rules of Thumb)

| Guideline | Recommendation |
|-----------|----------------|
| Shard size | 10GB–50GB per shard |
| Shards per node | < 20 shards per GB of heap |
| Docs per shard | Millions are fine, billions get slow |

> [!TIP]
> **Staff Formula**: For time-series data, calculate:
> ```
> daily_data_size / target_shard_size = shards_per_day
> ```
> Example: 100GB/day logs ÷ 25GB target = 4 primary shards per daily index.

---

## 6. Shard Allocation Awareness

ES can be told to spread shards across **zones** (racks, availability zones):

```json
PUT /_cluster/settings
{
  "persistent": {
    "cluster.routing.allocation.awareness.attributes": "zone"
  }
}
```

Then configure each node with its zone:
```yaml
# elasticsearch.yml
node.attr.zone: us-east-1a
```

Now ES ensures that a primary and its replica are never in the same zone.

---

## 7. Hands-on: Shard Exploration

### Step 1: Check current shard allocation
```bash
curl -X GET "http://localhost:9200/_cat/shards?v"
```

Output shows which node owns each shard.

### Step 2: Create index with specific shard count
```bash
curl -X PUT "http://localhost:9200/logs-demo" -H "Content-Type: application/json" -d '
{
  "settings": {
    "number_of_shards": 3,
    "number_of_replicas": 1
  }
}'
```

### Step 3: Observe shard distribution
```bash
curl -X GET "http://localhost:9200/_cat/shards/logs-demo?v"
```

You should see 3 primaries and 3 replicas distributed across your 3 nodes.

### Step 4: Index documents and check distribution
```bash
# Index 1000 documents
for i in $(seq 1 1000); do
  curl -s -X POST "http://localhost:9200/logs-demo/_doc" \
    -H "Content-Type: application/json" \
    -d "{\"message\": \"log entry $i\", \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" > /dev/null
done

# Refresh and check counts per shard
curl -X POST "http://localhost:9200/logs-demo/_refresh"
curl -X GET "http://localhost:9200/_cat/shards/logs-demo?v&h=index,shard,prirep,docs,store,node"
```

### Step 5: Simulate node failure
```bash
# Stop one node
docker stop es-node-2

# Wait a moment, then check cluster health
sleep 10
curl -X GET "http://localhost:9200/_cluster/health?pretty"

# Check shard allocation — replicas should be promoted or reallocated
curl -X GET "http://localhost:9200/_cat/shards/logs-demo?v"

# Bring node back
docker start es-node-2
```

### Step 6: Understand routing
```bash
# Index with custom routing (all docs with same routing go to same shard)
curl -X POST "http://localhost:9200/logs-demo/_doc?routing=user123" \
  -H "Content-Type: application/json" \
  -d '{"message": "user action", "user_id": "user123"}'

# Explain which shard a routing value maps to
curl -X GET "http://localhost:9200/logs-demo/_search_shards?routing=user123&pretty"
```

---

## 8. Rebalancing

When you add or remove nodes, ES automatically rebalances shards:

```
Before (2 nodes):           After adding Node 3:
Node 1: [P0, P1, P2]        Node 1: [P0, R1]
Node 2: [R0, R1, R2]        Node 2: [P1, R2]
                            Node 3: [P2, R0]
```

> [!WARNING]
> **Staff Insight**: Rebalancing is network and I/O intensive (shards are copied over the network). In production, you may want to:
> - Throttle recovery: `indices.recovery.max_bytes_per_sec`
> - Defer allocation during maintenance: `cluster.routing.allocation.enable: none`

---

## Your Task

1. **Routing experiment**: Create an index. Index 100 docs with random IDs. Index 100 more with `?routing=same-value`. Use `_cat/shards` to see doc distribution. What's different?

2. **Failure recovery**: With a 3-node cluster and 1 replica, stop 2 nodes. What happens to cluster health? Can you still read? Can you write?

3. **Shard sizing calculation**: You expect 500GB of data, want 30GB max per shard. How many primary shards do you need? What if you also want 1 replica?

---

## Solutions & Staff Level Insights

### Task 1: Routing effect
Random IDs spread evenly across all shards. Routing forces all 100 docs onto a single shard — visible in `_cat/shards` doc counts.

### Task 2: 2-node failure
- Cluster goes RED (some shards have no copies online)
- You might read from surviving shard(s) for their data
- Writes to indices with no available primary will fail

### Task 3: Shard calculation
- 500GB ÷ 30GB = ~17 primary shards (round up to 18)
- With 1 replica: 18 primaries + 18 replicas = 36 total shards
- Make sure you have enough nodes to hold them without overloading
