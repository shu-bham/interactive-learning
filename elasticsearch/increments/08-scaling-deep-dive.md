# Increment 08: Scaling Deep-Dive

Now that you understand shards and internals, let's discuss real-world scaling strategies for Elasticsearch.

---

## 1. Shard Sizing Revisited

### The Golden Rule

| Guideline | Value |
|-----------|-------|
| Optimal shard size | 10–50 GB |
| Max docs per shard | ~200 million (soft limit) |
| Shards per node | < 20 per GB of heap |

> [!IMPORTANT]
> **Staff Insight**: The 50GB upper limit exists because segment merges become slow and can cause long GC pauses. The lower limit (10GB) prevents the overhead of managing too many small shards.

### Calculating Shards for Time-Series Data

```
Daily Data Size: 200 GB
Target Shard Size: 25 GB
Primary Shards per Day: 200 / 25 = 8 shards

With 1 Replica: 8 × 2 = 16 shards/day

Retention: 30 days
Total Shards: 16 × 30 = 480 shards
```

---

## 2. Hot-Warm-Cold Architecture

For time-series data (logs, metrics), use tiered storage:

```
┌─────────────────────────────────────────────────────────────┐
│                         CLUSTER                             │
│                                                             │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │   HOT       │    │   WARM      │    │   COLD      │     │
│  │  (SSD)      │    │  (HDD)      │    │  (HDD/S3)   │     │
│  │             │    │             │    │             │     │
│  │ Today's     │    │ Last 7      │    │ Older than  │     │
│  │ logs        │    │ days        │    │ 7 days      │     │
│  │             │    │             │    │             │     │
│  │ Active      │    │ Read-only   │    │ Rarely      │     │
│  │ indexing    │    │ queries     │    │ accessed    │     │
│  └─────────────┘    └─────────────┘    └─────────────┘     │
└─────────────────────────────────────────────────────────────┘
```

### Node Configuration

```yaml
# Hot node (beefy, SSD)
node.attr.data: hot
node.roles: [data_hot]

# Warm node (medium, HDD)
node.attr.data: warm
node.roles: [data_warm]

# Cold node (cheap, archival)
node.attr.data: cold
node.roles: [data_cold]
```

---

## 3. Index Lifecycle Management (ILM)

ILM automates the journey of an index through phases:

```
HOT ────► WARM ────► COLD ────► DELETE
(index)   (shrink)   (freeze)   (after 90d)
```

### Creating an ILM Policy

```bash
curl -X PUT "http://localhost:9200/_ilm/policy/logs-policy" -H "Content-Type: application/json" -d '
{
  "policy": {
    "phases": {
      "hot": {
        "min_age": "0ms",
        "actions": {
          "rollover": {
            "max_size": "25gb",
            "max_age": "1d"
          },
          "set_priority": { "priority": 100 }
        }
      },
      "warm": {
        "min_age": "2d",
        "actions": {
          "shrink": { "number_of_shards": 1 },
          "forcemerge": { "max_num_segments": 1 },
          "allocate": {
            "require": { "data": "warm" }
          },
          "set_priority": { "priority": 50 }
        }
      },
      "cold": {
        "min_age": "7d",
        "actions": {
          "allocate": {
            "require": { "data": "cold" }
          },
          "set_priority": { "priority": 0 }
        }
      },
      "delete": {
        "min_age": "90d",
        "actions": {
          "delete": {}
        }
      }
    }
  }
}'
```

### Attach Policy to Index Template

```bash
curl -X PUT "http://localhost:9200/_index_template/logs-template" -H "Content-Type: application/json" -d '
{
  "index_patterns": ["logs-*"],
  "template": {
    "settings": {
      "number_of_shards": 4,
      "number_of_replicas": 1,
      "index.lifecycle.name": "logs-policy",
      "index.lifecycle.rollover_alias": "logs"
    }
  }
}'
```

---

## 4. Index Rollover

Instead of daily indices (`logs-2024-01-15`), use rollover:

```bash
# Create initial index
curl -X PUT "http://localhost:9200/logs-000001" -H "Content-Type: application/json" -d '
{
  "aliases": {
    "logs": { "is_write_index": true }
  }
}'

# Rollover when conditions met
curl -X POST "http://localhost:9200/logs/_rollover" -H "Content-Type: application/json" -d '
{
  "conditions": {
    "max_age": "1d",
    "max_size": "25gb",
    "max_docs": 10000000
  }
}'
```

After rollover:
- `logs-000001` becomes read-only
- `logs-000002` becomes the new write index
- Alias `logs` points to both for reading

> [!TIP]
> **Staff Insight**: Rollover + ILM is the recommended pattern for time-series data. It decouples your naming scheme from time, and ILM handles the rest automatically.

---

## 5. Shrink & Force Merge

### Shrink: Reduce Shard Count

```bash
# Prepare: make index read-only and move all to one node
curl -X PUT "http://localhost:9200/logs-000001/_settings" -H "Content-Type: application/json" -d '
{
  "index.blocks.write": true,
  "index.routing.allocation.require._name": "es-node-1"
}'

# Shrink from 4 shards to 1
curl -X POST "http://localhost:9200/logs-000001/_shrink/logs-000001-shrunk" -H "Content-Type: application/json" -d '
{
  "settings": {
    "index.number_of_shards": 1,
    "index.codec": "best_compression"
  }
}'
```

### Force Merge: Compact Segments

```bash
curl -X POST "http://localhost:9200/logs-000001-shrunk/_forcemerge?max_num_segments=1"
```

> [!WARNING]
> **Staff Insight**: Shrink requires all shards on one node temporarily. Plan for this disk space. Force merge should only be run on read-only indices.

---

## 6. Rebalancing Strategies

### Adding Nodes

When you add nodes, ES automatically rebalances. Control the speed:

```bash
# Throttle recovery to avoid overwhelming existing nodes
curl -X PUT "http://localhost:9200/_cluster/settings" -H "Content-Type: application/json" -d '
{
  "persistent": {
    "indices.recovery.max_bytes_per_sec": "100mb"
  }
}'
```

### Removing Nodes

First, exclude the node from allocation:

```bash
curl -X PUT "http://localhost:9200/_cluster/settings" -H "Content-Type: application/json" -d '
{
  "persistent": {
    "cluster.routing.allocation.exclude._name": "node-to-remove"
  }
}'
```

Wait for shards to relocate, then shut down.

---

## 7. Hands-on: ILM Setup

### Step 1: Create ILM policy
```bash
curl -X PUT "http://localhost:9200/_ilm/policy/demo-policy" -H "Content-Type: application/json" -d '
{
  "policy": {
    "phases": {
      "hot": {
        "actions": {
          "rollover": { "max_docs": 100 }
        }
      },
      "delete": {
        "min_age": "5m",
        "actions": { "delete": {} }
      }
    }
  }
}'
```

### Step 2: Create index template
```bash
curl -X PUT "http://localhost:9200/_index_template/demo-template" -H "Content-Type: application/json" -d '
{
  "index_patterns": ["demo-*"],
  "template": {
    "settings": {
      "number_of_shards": 1,
      "index.lifecycle.name": "demo-policy",
      "index.lifecycle.rollover_alias": "demo-logs"
    }
  }
}'
```

### Step 3: Bootstrap the first index
```bash
curl -X PUT "http://localhost:9200/demo-000001" -H "Content-Type: application/json" -d '
{
  "aliases": { "demo-logs": { "is_write_index": true } }
}'
```

### Step 4: Index documents and watch rollover
```bash
# Index 150 docs (should trigger rollover at 100)
for i in $(seq 1 150); do
  curl -s -X POST "http://localhost:9200/demo-logs/_doc" -H "Content-Type: application/json" -d "{\"msg\":\"log $i\"}" > /dev/null
done

# Check indices
curl -X GET "http://localhost:9200/_cat/indices/demo-*?v"
```

### Step 5: Check ILM status
```bash
curl -X GET "http://localhost:9200/demo-*/_ilm/explain?pretty"
```

---

## 8. Anti-Patterns to Avoid

| Anti-Pattern | Why It's Bad | Solution |
|--------------|--------------|----------|
| One shard per document type | Cluster state bloat | Use single index with `type` field |
| Daily indexes with 1 shard each | Too many small indices | Use rollover by size |
| Never deleting data | Unbounded growth | ILM delete phase |
| Same replica count everywhere | Wasted resources | Reduce replicas on cold data |

---

## Your Task

1. **ILM experiment**: Create a policy that rolls over at 50 docs and deletes after 2 minutes. Watch the lifecycle in action.

2. **Shrink experiment**: Create an index with 4 shards. Populate it. Shrink to 1 shard. Compare segment counts before and after.

3. **Capacity planning**: You expect 1TB/day of logs. Target 30GB shards, 30-day retention, 1 replica. How many total shards? How many data nodes do you need (assuming 64GB heap per node)?

---

## Solutions & Staff Level Insights

### Task 1: ILM lifecycle
After 2 minutes past rollover, the old index should be deleted. Check with `_cat/indices`.

### Task 2: Shrink
Before: 4 shards, potentially many segments. After: 1 shard with combined segments. Force merge to get to 1 segment total.

### Task 3: Capacity planning
- Daily: 1000GB / 30GB = 34 primary shards
- With replica: 68 shards/day
- 30 days: 2040 total shards
- Per node (20 shards/GB heap): 64GB * 20 = 1280 shards max
- Nodes needed: 2040 / 1280 ≈ 2 nodes minimum (add for headroom)

**Staff reality**: You'd want 4-6 data nodes for redundancy and to handle query load, not just storage.
