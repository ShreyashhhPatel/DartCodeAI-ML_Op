# DartCodeAI – Level 4 ML/Analytics Practical Assignment

Welcome to the DartCodeAI practical assessment. This assignment evaluates your ability to:
- extend an inference CLI with embeddings,
- reason about quotas/tokens,
- compute safe analytics deltas,
- benchmark + explain latency,
- and design a production-ready scaling approach.

**Timebox:** 2–4 hours. We’re assessing clarity, correctness, and production thinking.

---

## Folder Layout (you submit in this structure)

```
/modified_code
  /dart/bin/dartcodeai.dart
  /python/cli.py
  /python/requirements.txt
  /.env (optional)
/report
  benchmarks.md
  system_design.md
  reasoning.md
  self_assessment.md
```

> You may use any compatible model/endpoint (HuggingFace, OpenAI, etc.).

---

## Task 1 — Extend CLI With Vector Embeddings

Command:
```
dart run bin/dartcodeai.dart --task embed --text "docA|docB"
```

Requirements:
- Call an embedding model endpoint and retrieve vectors for `docA` and `docB`.
- Compute cosine similarity.
- Print JSON:
```json
{
  "status": 200,
  "latency_ms": 1234,
  "vector_dim": 768,
  "similarity_score": 0.72
}
```
Handle timeouts, HTTP errors, and malformed input.

---

## Task 2 — Implement Correct Quota Enforcement Logic

Write a function (language of your choice, but keep it in `dartcodeai.dart` or a small helper file):

```
bool canProcess(
  int predictedPromptTokens,
  int predictedCompletionTokens,
  int currentUsage,
  int maxTokens
)
```

Reject if:
- `predictedPromptTokens > 512`
- `predictedCompletionTokens > 512`
- `predictedPromptTokens + predictedCompletionTokens + currentUsage > maxTokens`

Include 2–3 lines of reasoning in `/report/reasoning.md`.

---

## Task 3 — Compute Safe Analytics Delta

Provide a Python function in `cli.py` (or separate helper) and include a short explanation in `/report/reasoning.md`:

```python
def compute_safe_delta(prev, curr):
    """Return a sane delta, correcting anomalies."""
```

Rules:
1. If `curr < prev` → delta = 0
2. If `curr - prev > 100 MB` → clamp to exactly 100 MB
3. If equal → delta = 0
4. Otherwise → delta = `curr - prev`

---

## Task 4 — Benchmarks & RCA

Run the CLI (either your Python wrapper or your Dart CLI) 10 times with a short prompt.
Submit in `/report/benchmarks.md`:
- a table of latencies (ms),
- min / max / average / p95,
- a brief RCA (3–5 sentences) explaining variance.

---

## Task 5 — System Design (Short, Practical)

Write `/report/system_design.md` (~10–15 sentences) describing how you would scale DartCodeAI to **10k requests/minute**:
- batching,
- caching,
- backpressure & retries,
- observability (metrics/logs/traces),
- degraded-mode/fallback behavior.

---

## Self‑Assessment (Required)

Fill `/report/self_assessment.md` honestly:
- What was **strong**?
- Where were you **weak** or ran out of time?
- What would you do with **one more day**?

---

## Running the Starter (optional helpers)

Minimal Python wrapper is included under `python/`. You may also call APIs directly from Dart.

Environment variables:
```
API_KEY=your_api_key
ENDPOINT_URL=https://api-inference.huggingface.co/models/sentence-transformers/all-MiniLM-L6-v2
```

---

## Submission Checklist

- Modified Dart CLI with `--task embed`.
- Cosine similarity implemented.
- Quota logic function present.
- Safe delta function present.
- Benchmarks + RCA included.
- System design included.
- Self‑assessment completed.

Good luck — we’re looking for pragmatic engineers who ship reliable systems.
