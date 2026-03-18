# Increment 06: Querying & Scoring

Understanding how ES finds and ranks documents is essential. This module covers the Query DSL and BM25 relevance scoring.

---

## 1. Query Context vs Filter Context

This is the most important concept in ES querying:

| Context | Scores? | Cached? | Use When |
|---------|---------|---------|----------|
| **Query** | Yes (relevance) | No | "How well does this match?" |
| **Filter** | No (yes/no) | Yes | "Does this match or not?" |

```json
{
  "query": {
    "bool": {
      "must": [
        { "match": { "title": "quick brown fox" } }    // Query context (scored)
      ],
      "filter": [
        { "term": { "status": "published" } },         // Filter context (not scored)
        { "range": { "date": { "gte": "2024-01-01" }}} // Filter context
      ]
    }
  }
}
```

> [!TIP]
> **Staff Insight**: Always use filter context for exact matches and ranges. Filter results are cached in a bitset, making repeated queries much faster. Only use query context when you need relevance scoring.

---

## 2. Common Query Types

### Match (Full-text search)
```json
{ "match": { "title": "quick fox" } }
```
Analyzes the query text, matches any term.

### Match Phrase (Exact phrase)
```json
{ "match_phrase": { "title": "quick brown fox" } }
```
Terms must appear in order, adjacent.

### Term (Exact value, no analysis)
```json
{ "term": { "status": "published" } }
```
For keyword fields. Does NOT analyze the query.

### Range
```json
{ "range": { "price": { "gte": 100, "lte": 500 } } }
```

### Bool (Compound query)
```json
{
  "bool": {
    "must": [],     // AND, affects score
    "should": [],   // OR, affects score  
    "must_not": [], // NOT, filter context
    "filter": []    // AND, no score, cached
  }
}
```

---

## 3. BM25: The Scoring Algorithm

ES uses **BM25** (Best Match 25) by default. It's an evolution of TF-IDF.

### The Formula (simplified)

```
score(q, d) = Σ IDF(qi) * (tf(qi, d) * (k1 + 1)) / (tf(qi, d) + k1 * (1 - b + b * |d|/avgdl))
```

Where:
- **tf** = term frequency (how often the term appears in the doc)
- **IDF** = inverse document frequency (rarer terms score higher)
- **|d|** = document length
- **avgdl** = average document length
- **k1** = term frequency saturation (default: 1.2)
- **b** = length normalization (default: 0.75)

> [!NOTE]
> **Staff Insight**: The key improvement of BM25 over TF-IDF is **term frequency saturation**. In TF-IDF, if a term appears 100 times, it scores 100x a term appearing once. In BM25, the curve flattens — diminishing returns after a certain frequency.

### Tuning BM25
```json
PUT /my-index
{
  "settings": {
    "similarity": {
      "my_bm25": {
        "type": "BM25",
        "k1": 1.2,
        "b": 0.75
      }
    }
  },
  "mappings": {
    "properties": {
      "content": {
        "type": "text",
        "similarity": "my_bm25"
      }
    }
  }
}
```

---

## 4. Explain API: Understanding Scores

```bash
GET /products/_explain/1
{
  "query": {
    "match": { "description": "laptop powerful" }
  }
}
```

Output shows the full score breakdown — which terms matched, their IDF, tf, etc.

---

## 5. Hands-on: Querying Deep-Dive

### Step 1: Create test data
```bash
curl -X PUT "http://localhost:9200/articles" -H "Content-Type: application/json" -d '
{
  "mappings": {
    "properties": {
      "title": { "type": "text" },
      "body": { "type": "text" },
      "category": { "type": "keyword" },
      "views": { "type": "integer" },
      "published": { "type": "date" }
    }
  }
}'

# Index test documents
curl -X POST "http://localhost:9200/articles/_bulk" -H "Content-Type: application/json" -d '
{"index":{"_id":"1"}}
{"title":"Elasticsearch Basics","body":"Elasticsearch is a distributed search engine built on Lucene","category":"tech","views":1000,"published":"2024-01-15"}
{"index":{"_id":"2"}}
{"title":"Advanced Elasticsearch","body":"Deep dive into Elasticsearch internals and scaling","category":"tech","views":500,"published":"2024-01-20"}
{"index":{"_id":"3"}}
{"title":"Database Comparison","body":"Comparing Elasticsearch with PostgreSQL and MySQL","category":"tech","views":2000,"published":"2024-01-10"}
{"index":{"_id":"4"}}
{"title":"Cooking Basics","body":"Learn the basics of cooking delicious meals","category":"food","views":300,"published":"2024-01-18"}
'

curl -X POST "http://localhost:9200/articles/_refresh"
```

### Step 2: Query vs Filter context
```bash
# Query context - scored by relevance
curl -X GET "http://localhost:9200/articles/_search?pretty" -H "Content-Type: application/json" -d '
{
  "query": {
    "match": { "body": "elasticsearch" }
  }
}'

# Filter context - no scoring, just yes/no
curl -X GET "http://localhost:9200/articles/_search?pretty" -H "Content-Type: application/json" -d '
{
  "query": {
    "bool": {
      "filter": [
        { "term": { "category": "tech" } }
      ]
    }
  }
}'
```

Notice the scores: query context has varying scores, filter context has constant scores (or 0 with track_total_hits).

### Step 3: Combine query and filter
```bash
curl -X GET "http://localhost:9200/articles/_search?pretty" -H "Content-Type: application/json" -d '
{
  "query": {
    "bool": {
      "must": [
        { "match": { "body": "elasticsearch" } }
      ],
      "filter": [
        { "term": { "category": "tech" } },
        { "range": { "views": { "gte": 500 } } }
      ]
    }
  }
}'
```

### Step 4: Use explain to understand scoring
```bash
curl -X GET "http://localhost:9200/articles/_explain/1?pretty" -H "Content-Type: application/json" -d '
{
  "query": {
    "match": { "body": "elasticsearch distributed" }
  }
}'
```

### Step 5: Boost specific fields
```bash
curl -X GET "http://localhost:9200/articles/_search?pretty" -H "Content-Type: application/json" -d '
{
  "query": {
    "multi_match": {
      "query": "elasticsearch basics",
      "fields": ["title^3", "body"]
    }
  }
}'
```

`title^3` means title matches are 3x more important than body matches.

---

## 6. Function Score: Custom Ranking

When BM25 isn't enough, use `function_score`:

```bash
curl -X GET "http://localhost:9200/articles/_search?pretty" -H "Content-Type: application/json" -d '
{
  "query": {
    "function_score": {
      "query": { "match": { "body": "elasticsearch" } },
      "functions": [
        {
          "field_value_factor": {
            "field": "views",
            "factor": 1.2,
            "modifier": "log1p",
            "missing": 1
          }
        },
        {
          "gauss": {
            "published": {
              "origin": "now",
              "scale": "30d",
              "decay": 0.5
            }
          }
        }
      ],
      "score_mode": "multiply",
      "boost_mode": "multiply"
    }
  }
}'
```

This:
- Boosts by popularity (`views` field)
- Boosts recent articles (decay function on `published`)

> [!IMPORTANT]
> **Staff Insight**: Function score is powerful but expensive. Each function is computed per document. For high-traffic queries, consider pre-computing a "popularity_score" field instead.

---

## 7. Common Search Patterns

### E-commerce Search
```json
{
  "query": {
    "bool": {
      "must": { "multi_match": { "query": "laptop", "fields": ["name^2", "description"] }},
      "filter": [
        { "term": { "in_stock": true }},
        { "range": { "price": { "lte": 1500 }}}
      ]
    }
  },
  "sort": [
    { "_score": "desc" },
    { "sales_count": "desc" }
  ]
}
```

### Log Search
```json
{
  "query": {
    "bool": {
      "filter": [
        { "range": { "@timestamp": { "gte": "now-1h" }}},
        { "term": { "level": "error" }}
      ],
      "must": { "match": { "message": "connection timeout" }}
    }
  },
  "sort": [{ "@timestamp": "desc" }]
}
```

---

## Your Task

1. **Filter cache test**: Run the same filter query twice. Use `GET /_nodes/stats/indices/query_cache` before and after. Did the cache hit increase?

2. **Score experiment**: Create 3 documents with the word "test" appearing 1, 5, and 20 times. Search for "test". What are the relative scores? Does 20 occurrences score 20x higher?

3. **Explain deep-dive**: For a multi-term query, use `_explain` to understand how IDF differs for common vs rare terms.

---

## Solutions & Staff Level Insights

### Task 1: Filter cache
The second identical filter query should show a cache hit. Filter caches are per-shard bitsets.

### Task 2: BM25 saturation
Due to BM25's saturation, 20 occurrences does NOT score 20x higher than 1 occurrence. The curve flattens — maybe 2-3x higher. This prevents keyword stuffing from dominating results.

### Task 3: IDF insight
Common terms (like "the") have low IDF → contribute little to score. Rare terms have high IDF → contribute more. This is why "the quick brown fox" matches mostly on "brown" and "fox", not "the".
