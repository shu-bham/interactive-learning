# Increment 09: Operational Patterns

Running Elasticsearch in production requires understanding circuit breakers, bulk operations, backups, and common operational patterns.

---

## 1. Circuit Breakers

ES has circuit breakers to prevent OutOfMemory errors:

| Breaker | Default | Protects Against |
|---------|---------|------------------|
| `parent` | 95% of heap | Total memory usage |
| `fielddata` | 40% of heap | In-memory fielddata (text field aggs) |
| `request` | 60% of heap | Single request memory |
| `in_flight_requests` | 100% of heap | Network buffer for requests |

When tripped:
```json
{
  "error": {
    "type": "circuit_breaking_exception",
    "reason": "[parent] Data too large, data for [<aggregation>] would be [1.5gb], which is larger than the limit of [1.2gb]"
  }
}
```

### Monitoring Circuit Breakers
```bash
curl -X GET "http://localhost:9200/_nodes/stats/breaker?pretty"
```

> [!WARNING]
> **Staff Insight**: Circuit breakers are your friend — they crash the query, not the node. If you're hitting them frequently, optimize your queries or add heap. Don't increase limits without understanding the cause.

---

## 2. Bulk Indexing Best Practices

### The Bulk API

```bash
curl -X POST "http://localhost:9200/_bulk" -H "Content-Type: application/json" -d '
{"index":{"_index":"products","_id":"1"}}
{"name":"Laptop","price":999}
{"index":{"_index":"products","_id":"2"}}
{"name":"Phone","price":699}
'
```

### Optimal Bulk Size

| Factor | Recommendation |
|--------|----------------|
| Request size | 5-15 MB |
| Document count | 1,000-5,000 per request |
| Parallel requests | 2-4 per node |

> [!TIP]
> **Staff Insight**: Don't go too large — ES needs to parse and hold the entire bulk in memory. Don't go too small — HTTP overhead dominates. Tune by measuring throughput.

### Bulk Indexing Settings

```bash
# Before bulk import
curl -X PUT "http://localhost:9200/my-index/_settings" -H "Content-Type: application/json" -d '
{
  "index": {
    "refresh_interval": "-1",
    "number_of_replicas": 0
  }
}'

# After bulk import
curl -X PUT "http://localhost:9200/my-index/_settings" -H "Content-Type: application/json" -d '
{
  "index": {
    "refresh_interval": "1s",
    "number_of_replicas": 1
  }
}'
curl -X POST "http://localhost:9200/my-index/_refresh"
```

---

## 3. Slow Log

Find slow queries and indexing operations:

```bash
curl -X PUT "http://localhost:9200/my-index/_settings" -H "Content-Type: application/json" -d '
{
  "index.search.slowlog.threshold.query.warn": "10s",
  "index.search.slowlog.threshold.query.info": "5s",
  "index.search.slowlog.threshold.fetch.warn": "1s",
  "index.indexing.slowlog.threshold.index.warn": "10s"
}'
```

Logs appear in `<ES_HOME>/logs/<cluster>_index_search_slowlog.json`.

---

## 4. Snapshot & Restore

### Register Repository (S3 example)

```bash
curl -X PUT "http://localhost:9200/_snapshot/my-s3-repo" -H "Content-Type: application/json" -d '
{
  "type": "s3",
  "settings": {
    "bucket": "my-es-backups",
    "region": "us-east-1"
  }
}'
```

### Create Snapshot

```bash
curl -X PUT "http://localhost:9200/_snapshot/my-s3-repo/snapshot-2024-01-15?wait_for_completion=true" -H "Content-Type: application/json" -d '
{
  "indices": "logs-*",
  "ignore_unavailable": true,
  "include_global_state": false
}'
```

### Restore Snapshot

```bash
curl -X POST "http://localhost:9200/_snapshot/my-s3-repo/snapshot-2024-01-15/_restore" -H "Content-Type: application/json" -d '
{
  "indices": "logs-2024-01-10",
  "rename_pattern": "(.+)",
  "rename_replacement": "restored-$1"
}'
```

> [!IMPORTANT]
> **Staff Insight**: Snapshots are incremental — only changed segments are uploaded. First snapshot is large; subsequent ones are fast. Schedule hourly or daily depending on RPO.

---

## 5. Cross-Cluster Replication (CCR)

For disaster recovery across datacenters:

```
DC-1 (Leader)              DC-2 (Follower)
┌─────────────┐            ┌─────────────┐
│ logs-000001 │ ─────────► │ logs-000001 │
│ (writable)  │  replicate │ (read-only) │
└─────────────┘            └─────────────┘
```

```bash
# On follower cluster
curl -X PUT "http://follower:9200/logs-000001/_ccr/follow" -H "Content-Type: application/json" -d '
{
  "remote_cluster": "leader-dc",
  "leader_index": "logs-000001"
}'
```

---

## 6. Cross-Cluster Search (CCS)

Query multiple clusters at once:

```bash
# Configure remote cluster
curl -X PUT "http://localhost:9200/_cluster/settings" -H "Content-Type: application/json" -d '
{
  "persistent": {
    "cluster.remote.dc2.seeds": ["dc2-node1:9300", "dc2-node2:9300"]
  }
}'

# Search both clusters
curl -X GET "http://localhost:9200/local-index,dc2:remote-index/_search" -H "Content-Type: application/json" -d '
{
  "query": { "match_all": {} }
}'
```

---

## 7. Hands-on: Operational Tasks

### Step 1: Monitor cluster health in detail
```bash
# Cluster health
curl -X GET "http://localhost:9200/_cluster/health?pretty"

# Node stats (CPU, memory, disk)
curl -X GET "http://localhost:9200/_nodes/stats?pretty" | jq '.nodes[] | {name: .name, heap_used_percent: .jvm.mem.heap_used_percent, cpu_percent: .os.cpu.percent}'

# Index stats
curl -X GET "http://localhost:9200/_stats?pretty" | jq '.indices | to_entries[] | {index: .key, docs: .value.primaries.docs.count, size: .value.primaries.store.size_in_bytes}'
```

### Step 2: Bulk index with optimal settings
```bash
# Disable refresh
curl -X PUT "http://localhost:9200/bulk-demo/_settings" -H "Content-Type: application/json" -d '
{"index": {"refresh_interval": "-1"}}'

# Bulk index
for batch in $(seq 1 10); do
  DATA=""
  for i in $(seq 1 500); do
    DATA="$DATA{\"index\":{}}\n{\"msg\":\"bulk message $batch-$i\"}\n"
  done
  echo -e "$DATA" | curl -s -X POST "http://localhost:9200/bulk-demo/_bulk" -H "Content-Type: application/json" --data-binary @- > /dev/null
done

# Re-enable refresh
curl -X PUT "http://localhost:9200/bulk-demo/_settings" -H "Content-Type: application/json" -d '
{"index": {"refresh_interval": "1s"}}'
curl -X POST "http://localhost:9200/bulk-demo/_refresh"

# Check doc count
curl -s "http://localhost:9200/bulk-demo/_count" | jq
```

### Step 3: Create and restore a snapshot (filesystem repo)
```bash
# Register local filesystem repo (for demo)
curl -X PUT "http://localhost:9200/_snapshot/local-backup" -H "Content-Type: application/json" -d '
{
  "type": "fs",
  "settings": {
    "location": "/usr/share/elasticsearch/backup"
  }
}'

# Note: You need to configure path.repo in elasticsearch.yml first
# For docker, add: path.repo: /usr/share/elasticsearch/backup

# Create snapshot
curl -X PUT "http://localhost:9200/_snapshot/local-backup/snap1?wait_for_completion=true" -H "Content-Type: application/json" -d '
{
  "indices": "bulk-demo"
}'

# List snapshots
curl -X GET "http://localhost:9200/_snapshot/local-backup/_all?pretty"
```

### Step 4: Check for slow queries
```bash
# Enable slow log
curl -X PUT "http://localhost:9200/bulk-demo/_settings" -H "Content-Type: application/json" -d '
{
  "index.search.slowlog.threshold.query.info": "0ms"
}'

# Run a query
curl -X GET "http://localhost:9200/bulk-demo/_search" -H "Content-Type: application/json" -d '
{"query": {"match_all": {}}}'

# Check slow log (inside container)
# docker exec es-node-1 cat /usr/share/elasticsearch/logs/*slowlog.json
```

---

## 8. Common Operational Runbooks

### Cluster Yellow (missing replicas)
```bash
# Check unassigned shards
curl -X GET "http://localhost:9200/_cat/shards?v&h=index,shard,prirep,state,unassigned.reason" | grep UNASSIGNED

# Get allocation explanation
curl -X GET "http://localhost:9200/_cluster/allocation/explain?pretty"

# Common fix: add nodes or reduce replica count
curl -X PUT "http://localhost:9200/my-index/_settings" -H "Content-Type: application/json" -d '
{"index": {"number_of_replicas": 0}}'
```

### Cluster Red (missing primaries)
```bash
# Identify red indices
curl -X GET "http://localhost:9200/_cat/indices?v&health=red"

# Try to recover from translog
curl -X POST "http://localhost:9200/my-index/_open"

# Last resort: allocate stale shard (DATA LOSS RISK)
curl -X POST "http://localhost:9200/_cluster/reroute" -H "Content-Type: application/json" -d '
{
  "commands": [{
    "allocate_stale_primary": {
      "index": "my-index",
      "shard": 0,
      "node": "node-1",
      "accept_data_loss": true
    }
  }]
}'
```

### High Heap Usage
```bash
# Check heap
curl -s "http://localhost:9200/_nodes/stats" | jq '.nodes[] | {name: .name, heap_percent: .jvm.mem.heap_used_percent}'

# Clear fielddata cache
curl -X POST "http://localhost:9200/_cache/clear?fielddata=true"

# Check what's using memory
curl -X GET "http://localhost:9200/_cat/fielddata?v"
```

---

## 9. Monitoring Checklist

| Metric | Warning | Critical |
|--------|---------|----------|
| Cluster health | Yellow | Red |
| Heap used | >75% | >85% |
| Disk used | >80% | >90% |
| Search latency p99 | >1s | >5s |
| Indexing rate drop | >20% | >50% |
| Pending tasks | >10 | >50 |

> [!TIP]
> **Staff Insight**: Use Kibana Stack Monitoring, Prometheus + Grafana, or Datadog for visualization. The `_cat` and `_stats` APIs are your friends for debugging, but not for continuous monitoring.

---

## Your Task

1. **Bulk tuning**: Index 100,000 documents. Test with bulk sizes of 100, 1000, and 5000. Measure total time. Which is fastest?

2. **Circuit breaker trigger**: Create a high-cardinality field. Run a terms aggregation with size:100000. Does it trip a circuit breaker?

3. **Disaster recovery plan**: Document a runbook for your team: How to snapshot, how to restore, how to handle node failures.

---

## Solutions & Staff Level Insights

### Task 1: Bulk size tuning
Typically, 1000-5000 docs per bulk is optimal. Too small = HTTP overhead. Too large = memory pressure. Your mileage varies based on doc size and cluster resources.

### Task 2: Circuit breaker
With truly high cardinality (millions of unique values), you'll likely hit the request or parent circuit breaker. The error message tells you which one and how much memory was requested.

### Task 3: DR runbook
Key elements:
- Snapshot schedule (e.g., hourly to S3)
- Restore procedure tested quarterly
- Failover to follower cluster (if using CCR)
- Communication plan for outages
