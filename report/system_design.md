# System Design — Scaling DartCodeAI to 10k Requests/Minute

## Overview

Scaling DartCodeAI from a CLI tool to handle 10,000 requests/minute (~167 req/sec) requires addressing throughput, latency, reliability, and observability. The core challenge: if 1,000 users hit "Enter" simultaneously, synchronous processing would crash servers trying to open 1,000 concurrent connections.

---

## 1. Asynchronous Architecture with Message Queuing

**Problem:** Synchronous request handling cannot absorb traffic spikes without cascading failures.

**Solution:** Implement a Message Queue (Kafka/RabbitMQ) to decouple input from processing.

**How It Works:**
- User request → immediate acknowledgment ("Request received")
- Request placed in queue (bounded at 1,000 pending)
- Worker processes pull at maximum safe throughput
- If traffic spikes to 20k/min for 10 seconds, queue grows but servers don't crash

**Benefit:** Natural load leveling prevents cascading failures. Workers process at constant safe speed regardless of input spikes.

---

## 2. Batching Strategy — GPU Efficiency

**Problem:** AI models on GPUs prefer one massive calculation over many tiny ones. Sending 167 individual requests/second wastes GPU cycles on network overhead.

**Solution:** Batch aggregator waits briefly to collect 16-64 requests, sends as single API call.

**Implementation:**
```python
# Dual-trigger batching
if batch_size >= 16 or time_since_first_request >= 50ms:
    flush_batch_to_api()
```

- Time-based flush: 50ms max wait (no user waits longer)
- Size-based flush: batch full at 16 documents
- **Impact:** Reduces API calls from 20,000/min to ~1,250/min (16x reduction)

**Why This Works:** GPUs excel at parallel matrix operations. Processing 64 embeddings takes barely longer than processing 1. We trade 50ms latency for 16x throughput.

---

## 3. Multi-Tier Caching Layer

**Problem:** Significant portion of embedding queries are repetitive (same code snippets, documentation, common questions).

**Solution:** Two-tier cache architecture with Redis + in-memory LRU.

**Implementation:**
```
Request → In-Memory LRU (hot data, <1ms)
   ↓ MISS
   → Redis Cache (warm data, <10ms)
   ↓ MISS
      → Embedding API (cold data, 800ms-2s)
```

**Cache Strategy:**
- Key: Hash of normalized input (lowercase + trim + collapse_whitespace)
- TTL: 24 hours (embeddings are deterministic)
- Expected hit rate: 40-60% for enterprise workloads

**Benefit:** Cache hits return in <10ms vs. 800ms+ for API calls, reducing costs by ~50%

---

## 4. Backpressure & Retry Logic

### Token Bucket Rate Limiting

Like a club bouncer: system has 10,000 tokens (refilling at 167/sec). Each request consumes one token. Empty bucket → immediate HTTP 429 with `Retry-After` header.

### Queue Depth Control

- Bounded queues: max 1,000 pending requests
- Tail-drop policy: new requests rejected with 503 when full
- Clear backpressure signals prevent queue exhaustion

### Exponential Backoff with Jitter

Client-side retry strategy prevents "thundering herd":

| Retry | Wait Time |
|-------|-----------|
| 1st | 100ms + random(0-50ms) |
| 2nd | 200ms + random(0-100ms) |
| 3rd | 400ms + random(0-200ms) |
| Max | 10 seconds |

Jitter randomization prevents all clients retrying simultaneously after outage recovery.

---

## 5. Observability — Metrics, Logs, Traces

### Metrics (Prometheus/Grafana)

Real-time dashboards tracking RED metrics (Rate, Errors, Duration):

| Metric | Warning | Critical |
|--------|---------|----------|
| P95 Latency | >2s | >5s |
| Error Rate | >0.5% | >2% |
| Queue Depth | >500 | >800 |
| Cache Hit Rate | <40% | <25% |

### Structured Logs (JSON)

Every request logs correlation ID, input hash (privacy-safe), latency breakdown:

```json
{
  "request_id": "req_abc123",
  "input_hash": "sha256:7f3a...",
  "latency_breakdown": {
    "queue_wait_ms": 12,
    "batch_wait_ms": 45,
    "api_call_ms": 180,
    "total_ms": 237
  },
  "cache_hit": false,
  "retry_count": 0
}
```

### Distributed Traces (OpenTelemetry)

Track single request through entire journey:

```
User → API Gateway → Queue → Batch → Embedding API → Response
       └─ 5ms ────└─ 12ms ─└─ 45ms ─└─ 180ms ────┘
```

---

## 6. Degraded Mode & Fallback Tiers

### Circuit Breaker Pattern

- **Closed:** Normal operation, requests pass through
- **Open:** After 5 consecutive failures, reject immediately (fail fast)
- **Half-Open:** After 30s, allow one test request to check recovery

### Fallback Strategy

| Tier | Trigger | Action |
|------|---------|--------|
| 1 | Primary API >3s latency | Switch to Cohere/OpenAI |
| 2 | All APIs unavailable | Extend cache TTL to 72h, serve stale |
| 3 | Cache miss during outage | Fall back to TF-IDF/BM25 (local, no API) |
| 4 | Circuit breaker open | Return 503 with estimated recovery time |

### Degraded Mode Features

- Disable detailed similarity explanations
- Skip secondary enrichment APIs
- Reduce batch wait time (faster but less efficient)

---

## Architecture Diagram

```
                    ┌─────────────────┐
                    │  Load Balancer  │
                    │ (Health checks) │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │  API Gateway    │
                    │ (Rate limiting) │
                    │  167 req/sec    │
                    └────────┬────────┘
                             │
              ┌──────────────┴──────────────┐
              ▼                             ▼
      ┌──────────────┐            ┌──────────────┐
      │ Redis Cache  │            │ Kafka Queue  │
      │  (Check 1st) │            │ (Async proc) │
      └──────┬───────┘            └──────┬───────┘
             │                           │
    HIT?────┴────MISS?                   ▼
             │                    ┌──────────────┐
             │                    │   Batch      │
             │                    │ Aggregator   │
             │                    │  (50ms max)  │
             │                    └──────┬───────┘
             │                           │
             │              ┌────────────┴────────────┐
             │              ▼                         ▼
             │     ┌──────────────┐         ┌──────────────┐
             │     │  Primary API │◄───────▶│ Fallback API │
             │     │(HuggingFace) │         │(Cohere/GPT)  │
             │     └──────┬───────┘         └──────────────┘
             │            │
             │     ┌──────────────┐
             │     │ Cache Write  │
             │     └──────┬───────┘
             │            │
             └────────────┴──────────────▶ Response
```

---

## Capacity Planning & Expected Performance

### Infrastructure Sizing

| Component | Specification | Purpose |
|-----------|--------------|---------|
| Load Balancer | 2 instances (active-passive) | SSL termination, geographic routing |
| API Gateway | 2 instances @ 500 req/sec each | Auth, rate limiting, request validation |
| Kafka Cluster | 3 nodes, 1M msgs/hour | Spike absorption, async processing |
| Batch Service | 4 instances @ 50 batches/sec | GPU-efficient aggregation |
| Redis Cache | 3-node cluster, 10GB, 50k ops/sec | Sub-10ms cache hits |
| Embedding API | 25k calls/min quota | Primary + 2 fallback providers |

### Performance Targets

| Metric | Target |
|--------|--------|
| P50 Latency | <200ms (cached), <800ms (uncached) |
| P95 Latency | <500ms (cached), <2s (uncached) |
| P99 Latency | <1s (cached), <3s (uncached) |
| Availability | 99.9% (8.7 hours downtime/year) |
| Cache Hit Rate | >50% |
| Error Rate | <0.5% |

---

## Cost Optimization

At 10k req/min (14.4M req/day):

- **Without optimizations:** 14.4M API calls @ $0.0001/call = **$1,440/day**
- **With 50% cache hits:** 7.2M API calls = **$720/day** (50% savings)
- **With batching (16x):** 450k API calls = **$45/day** (97% savings)

**ROI:** Redis infrastructure costs ~$200/month but saves $43k/month in API costs.

---

## Deployment Strategy

- **Blue-Green Deployment:** Run old + new versions simultaneously, switch traffic gradually
- **Canary Releases:** Route 5% of traffic to new version, monitor errors, scale to 100%
- **Health Checks:** API Gateway polls `/health` endpoint every 10s, removes unhealthy instances
- **Rolling Updates:** Update 25% of instances at a time, wait for health checks between batches

---

## Monitoring & Alerting

### Critical Alerts (PagerDuty)
- Error rate >2% for 5 minutes
- P95 latency >5s for 3 minutes
- Queue depth >800 for 2 minutes
- Cache cluster <2 healthy nodes

### Warning Alerts (Slack)
- Cache hit rate <40% for 15 minutes
- Embedding API latency >3s (switch to fallback)
- Retry rate >10% for 10 minutes

---

## Summary

This architecture scales DartCodeAI from a CLI tool to a production service by:

- **Decoupling** input (queue) from processing (workers) for spike absorption
- **Batching** requests for 16x GPU efficiency gains
- **Caching** 50% of requests to reduce costs and improve latency
- **Degrading gracefully** with fallback tiers and circuit breakers
- **Observing everything** with metrics, logs, and distributed traces

**The system handles 10k req/min with <2s P95 latency, 99.9% availability, and 97% cost savings vs. naive implementation.**
