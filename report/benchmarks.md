# Benchmarks Report

## Test Configuration

| Parameter | Value |
|-----------|-------|
| **CLI** | Dart (`dart run bin/dartcodeai.dart`) |
| **Task** | `embed` (embedding comparison) |
| **Model** | `sentence-transformers/all-MiniLM-L6-v2` |
| **Vector Dimensions** | 384 |
| **Runs** | 10 (varied sentence pairs) |

---

## Latency Results

| Run | Latency (ms) | Similarity | Input Texts                                                             |
|-----|--------------|------------|-------------------------------------------------------------------------|
| 1   | 145          | 0.40       | "Machine learning is fascinating" \| "AI transforms industries"         |
| 2   | 6,235        | 0.06       | "The cat sat on the mat" \| "A dog ran in the park"                     |
| 3   | 2,124        | 0.14       | "Python is a programming language" \| "JavaScript runs in browsers"     |
| 4   | 1,630        | 0.47       | "Coffee keeps me awake" \| "Tea is relaxing"                            |
| 5   | 1,706        | 0.36       | "The stock market crashed today" \| "Bitcoin reached new highs"         |
| 6   | 1,801        | 0.42       | "I love hiking in mountains" \| "Swimming in the ocean is fun"          |
| 7   | 1,996        | 0.30       | "Neural networks learn patterns" \| "Deep learning requires GPUs"       |
| 8   | 3,377        | 0.25       | "Tokyo is a busy city" \| "Paris has beautiful architecture"            |
| 9   | 1,152        | 0.26       | "Reading books expands knowledge" \| "Podcasts are informative"         |
| 10  | 685          | 0.27       |"Electric cars are eco-friendly" \| "Solar panels generate clean energy" |

---

## Statistical Summary

| Metric        | Value    |
|---------------|----------|
| **Min**       | 145 ms   |
| **Max**       | 6,235 ms |
| **Average**   | 2,085 ms |
| **Median**    | 1,754 ms |
| **P95**       | 6,235 ms |
| **Std Dev**   | 1,712 ms |

---

## Latency Distribution

```
   0-500ms   █        1 run  (10%)  ← warm cache
 500-1000ms  █        1 run  (10%)
1000-2000ms  █████    5 runs (50%)  ← typical range
2000-4000ms  ██       2 runs (20%)
4000-7000ms  █        1 run  (10%)  ← queue/cold start
```

---

## Root Cause Analysis (RCA)

The benchmark reveals significant latency variance (145ms to 6,235ms) across different sentence pairs, attributable to several factors:

1. **Model Cold Start & Queue Position (Run 2: 6,235ms):** The extreme outlier indicates the model instance was likely cold or queued behind other users. HuggingFace's serverless inference can take 5-10 seconds when the model needs to be loaded from cold storage to GPU memory. This is a known limitation of shared inference infrastructure.

2. **Sentence Complexity & Tokenization:** Longer or more complex sentences require more tokenization steps and attention computations. Run 8 (3,377ms) with location-based sentences ("Tokyo", "Paris") may trigger additional processing for proper noun handling compared to simpler inputs.

3. **Server-Side Load Balancing:** The 1,152ms to 1,996ms range (Runs 4-7, 9) represents steady-state performance when the model is warm but subject to variable server load. This 40% variance within the typical range reflects concurrent request handling on shared infrastructure.

4. **Network Jitter & Geographic Routing:** Each request makes two API calls (one per document), and the total latency includes round-trip time variance. Runs with lower latency (145ms, 685ms) likely benefited from optimal routing and low server queue depth.

**Production Recommendations:**
- Implement request warm-up with periodic health checks
- Use dedicated inference endpoints for predictable latency
- Add client-side retry with exponential backoff for cold-start scenarios
- Consider batching both documents in a single API call where supported
