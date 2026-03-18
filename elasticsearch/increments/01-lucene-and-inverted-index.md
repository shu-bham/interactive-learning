# Increment 01: Lucene & The Inverted Index

Elasticsearch is a distributed wrapper around **Apache Lucene**. To truly understand ES, you must understand Lucene's core data structure: the **inverted index**.

---

## 1. What is an Inverted Index?

In a relational database, you have a table and then create a B-tree index on specific columns.

In Lucene, the **inverted index IS the primary data structure** — not an afterthought.

### Forward Index (what you're used to)
```
Doc 1 → ["the", "quick", "brown", "fox"]
Doc 2 → ["the", "lazy", "dog"]
Doc 3 → ["quick", "fox", "jumps"]
```

### Inverted Index (what Lucene uses)
```
"brown"  → [1]
"dog"    → [2]
"fox"    → [1, 3]
"jumps"  → [3]
"lazy"   → [2]
"quick"  → [1, 3]
"the"    → [1, 2]
```

> [!NOTE]
> **Why "inverted"?** Instead of "document → words", it's "word → documents". This makes searching for a word O(1) lookup instead of scanning all documents.

---

## 2. Anatomy of a Lucene Index

A single Lucene index (which ES calls a "shard") contains:

```
┌───────────────────────────────────────────┐
│               LUCENE INDEX                │
├───────────────────────────────────────────┤
│  Segment 1       Segment 2       Segment N│
│  ┌─────────┐    ┌─────────┐    ┌─────────┐│
│  │Term Dict│    │Term Dict│    │Term Dict││
│  │Postings │    │Postings │    │Postings ││
│  │Stored   │    │Stored   │    │Stored   ││
│  │Doc Values│   │Doc Values│   │Doc Values│
│  └─────────┘    └─────────┘    └─────────┘│
└───────────────────────────────────────────┘
```

### Key structures per segment:

| Structure | Purpose | Analogy to RDBMS |
|-----------|---------|------------------|
| **Term Dictionary** | Sorted list of all unique terms | Like a B-tree's keys |
| **Postings List** | For each term, the list of doc IDs containing it | Like a B-tree's leaf pointers |
| **Stored Fields** | The original `_source` JSON | Like the actual row data |
| **Doc Values** | Columnar storage for sorting/aggregations | Like a covering index |

---

## 3. The Analyzer Pipeline

Before a document is indexed, text goes through an **analyzer**:

```
"The QUICK brown-fox"
        │
        ▼
┌─────────────────┐
│  Char Filters   │  (e.g., strip HTML)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   Tokenizer     │  (split into tokens)
└────────┬────────┘
         │
    ["The", "QUICK", "brown", "fox"]
         │
         ▼
┌─────────────────┐
│  Token Filters  │  (lowercase, stemming, stop words)
└────────┬────────┘
         │
    ["the", "quick", "brown", "fox"]
         │
         ▼
    Stored in Inverted Index
```

> [!IMPORTANT]
> **Staff Insight**: The same analyzer must be used at **index time** AND **query time**, otherwise "QUICK" indexed as "quick" won't match a query for "QUICK" that isn't lowercased.

### Common Analyzers

| Analyzer | What it does |
|----------|--------------|
| `standard` | Lowercase, removes punctuation, splits on whitespace |
| `simple` | Splits on non-letter chars, lowercases |
| `whitespace` | Splits only on whitespace, no lowercasing |
| `keyword` | No analysis — treats entire field as single token |
| `english` | Standard + stemming ("running" → "run") + stop words |

---

## 4. Segments: Immutable Mini-Indexes

Each segment is a **complete, self-contained, immutable** mini-index.

### Why immutable?
1. **No locking needed** for reads — massive concurrency win
2. **Filesystem caching** works perfectly (OS can cache segments aggressively)
3. **Compression** works better on immutable data

### The catch
- Deletes don't actually remove data — they mark documents as "deleted" in a `.del` file
- Updates = delete old + insert new
- Eventually, **segment merges** clean up deleted docs and combine small segments

```
Before merge:
[Seg1: 100 docs, 20 deleted] [Seg2: 50 docs, 5 deleted] [Seg3: 30 docs, 0 deleted]

After merge:
[MergedSeg: 155 docs, 0 deleted]  ← Deleted docs are gone, disk reclaimed
```

> [!WARNING]
> **Staff Insight**: Segment merges are CPU and I/O intensive. If you have high indexing throughput, you'll see periodic I/O spikes during merges. Configure `index.merge.policy` carefully for production workloads.

---

## 5. Hands-on: Explore the Inverted Index

### Step 1: Create an index with custom analyzer
```bash
curl -X PUT "http://localhost:9200/blog" -H "Content-Type: application/json" -d '
{
  "settings": {
    "analysis": {
      "analyzer": {
        "my_english": {
          "type": "custom",
          "tokenizer": "standard",
          "filter": ["lowercase", "english_stemmer"]
        }
      },
      "filter": {
        "english_stemmer": {
          "type": "stemmer",
          "language": "english"
        }
      }
    }
  },
  "mappings": {
    "properties": {
      "title": { "type": "text", "analyzer": "my_english" },
      "body": { "type": "text", "analyzer": "my_english" }
    }
  }
}'
```

### Step 2: Test the analyzer
```bash
curl -X POST "http://localhost:9200/blog/_analyze?pretty" -H "Content-Type: application/json" -d '
{
  "analyzer": "my_english",
  "text": "The quick foxes are running quickly"
}'
```

You'll see tokens like: `["quick", "fox", "run", "quick"]` — notice stemming!

### Step 3: Index some documents
```bash
curl -X POST "http://localhost:9200/blog/_doc/1" -H "Content-Type: application/json" -d '
{"title": "Running with foxes", "body": "The quick fox runs through the forest"}'

curl -X POST "http://localhost:9200/blog/_doc/2" -H "Content-Type: application/json" -d '
{"title": "Database internals", "body": "PostgreSQL uses B-trees for indexing"}'

curl -X POST "http://localhost:9200/blog/_refresh"
```

### Step 4: See the term vectors (inverted index peek)
```bash
curl -X GET "http://localhost:9200/blog/_termvectors/1?fields=body&pretty"
```

This shows you the actual terms stored in the inverted index for document 1.

### Step 5: Observe segments
```bash
curl -X GET "http://localhost:9200/blog/_segments?pretty"
```

You'll see segment details including document count, deleted docs, and size.

---

## 6. Comparison: MySQL Full-Text vs ES Inverted Index

| Aspect | MySQL Full-Text | Elasticsearch |
|--------|-----------------|---------------|
| Index structure | Auxiliary FTS index (InnoDB) | Primary inverted index |
| Analyzer | Limited (natural language modes) | Fully customizable pipeline |
| Relevance | Basic TF-IDF or boolean | BM25 + scriptable scoring |
| Updates | Can update in-place | Delete + re-insert (segment-based) |
| Distributed | Single node | Built-in sharding |

> [!NOTE]
> **Staff Insight**: MySQL's full-text search is an add-on to a row store. Lucene (ES) is built from the ground up for search. That's why ES beats MySQL FTS on scoring quality, flexibility, and scale.

---

## Your Task

1. **Analyzer experiment**: Using the `_analyze` API, compare `standard`, `english`, and `keyword` analyzers on the text "Running databases efficiently". What tokens does each produce?

2. **Term frequency**: Index 3 documents where one mentions "database" 5 times, another mentions it 2 times, and the third once. Use `_termvectors` to see the term frequencies.

3. **Segment observation**: Index 50 documents one by one (with refresh between each). Check `_segments`. How many segments exist? Now call `POST /blog/_forcemerge?max_num_segments=1` and check again.

---

## Solutions & Staff Level Insights

### Task 1: Analyzer comparison
- `standard`: ["running", "databases", "efficiently"]
- `english`: ["run", "databas", "effici"] (stemmed)
- `keyword`: ["Running databases efficiently"] (single token)

### Task 2: Term frequencies
The `_termvectors` response will show `term_freq: 5`, `term_freq: 2`, etc. This is one input to relevance scoring.

### Task 3: Segment behavior
You'll likely see ~50 segments initially (one per refresh). After force merge, you'll have 1 segment. 

**Staff Warning**: Never run `_forcemerge` on a write-heavy index — it blocks all indexing and hammers I/O. It's meant for read-only indices (like yesterday's logs in a time-series pattern).
