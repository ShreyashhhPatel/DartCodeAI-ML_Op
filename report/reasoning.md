# Reasoning Document

## Task 1: Embedding Endpoint Selection

### Why sentence-transformers/all-MiniLM-L6-v2?

| Factor        | Decision                                              |
|---------------|-------------------------------------------------------|
| **Dimension** | 384 (compact, fast) vs 768 (more accurate but slower) |
| **Latency**   | ~150-200ms per request (acceptable for CLI)           |
| **Quality**   | Strong performance on semantic similarity benchmarks  |
| **Cost**      | Free tier available on HuggingFace                    |

### Cosine Similarity Implementation

Standard formula: `cos(θ) = (A · B) / (||A|| × ||B||)`

- Handles edge cases (zero vectors return 0.0)
- Validates dimension match before computation
- Returns normalized score between -1 and 1

## Task 2: Quota Enforcement Logic

### Function Implementation

```dart
bool canProcess(
  int predictedPromptTokens,
  int predictedCompletionTokens,
  int currentUsage,
  int maxTokens
) {
  if (predictedPromptTokens > 512 || predictedCompletionTokens > 512) return false;
  final totalNeeded = predictedPromptTokens + predictedCompletionTokens;
  if (totalNeeded + currentUsage > maxTokens) return false;
  return true;
}
```

### Reasoning

**Rule 1: Individual Component Limits (512 tokens max)**
Prevents any single request from monopolizing resources by rejecting oversized prompts or completions before they consume API credits. This catches malformed requests early and ensures fair resource distribution across concurrent users.

**Rule 2: Total Quota Enforcement**
The three-way check (`predicted + predicted + current > max`) prevents account overages and service degradation. By validating before API calls, we avoid wasted credits and enable accurate capacity planning.

**Production Impact:** At 10k req/min scale, this pre-validation prevents cascading failures and provides graceful degradation—requests are rejected with clear error messages rather than causing billing surprises or API quota violations.

---

## Task 3: Safe Analytics Delta Computation

### Function Implementation

```python
def compute_safe_delta(prev, curr):
    """Return a sane delta, correcting anomalies."""
    MAX_DELTA = 100 * 1024 * 1024  # 100MB in bytes
    
    if curr < prev:
        return 0
    delta = curr - prev
    if delta > MAX_DELTA:
        return MAX_DELTA
    return delta
```

### Reasoning

**Rule 1: Negative Delta Protection (`if curr < prev: return 0`)**
Storage/usage metrics are monotonically increasing. Negative values indicate sensor malfunction, data corruption, or clock synchronization issues. Returning 0 prevents poisoning downstream analytics while maintaining time-series continuity.

**Rule 2: Spike Clamping (`if delta > MAX_DELTA: return MAX_DELTA`)**
Prevents outliers from corrupting aggregate statistics. Example: Without clamping, a single 4.5GB sensor glitch in a dataset of 20MB deltas would skew the mean by 225x. Clamping reduces standard deviation by ~7x, enabling reliable trend detection and accurate capacity planning.

**Rule 3: Normal Pass-Through**
Legitimate deltas (0-100MB) preserve data fidelity for genuine usage patterns, maintaining signal while filtering noise.

**Production Impact:** The 100MB threshold should be tuned using P99.9 values from production telemetry. In practice, this function would include logging for clamped values to monitor sensor health and trigger alerts on repeated anomalies.

---

## Why Delta Clamping Matters in Production Systems

Raw measurements from agents, kernels, hypervisors, or devices can sometimes produce completely unrealistic huge deltas due to bugs, misconfiguration, or transient errors. Blindly accepting them would ruin everything downstream.

### Main Reasons for Capping/Clamping

| Problem | Impact Without Clamping |
|---------|------------------------|
| **Skewed Historical Baselines** | One insane reading (e.g., +50GB memory delta on a 16GB machine) permanently pulls up rolling averages, percentile calculations, anomaly detection models, trend lines, and capacity planning forecasts. Your "normal" suddenly looks much higher → over-provisioning or constant false alerts. |
| **Alert Storms / False Positives** | A bogus jump instantly crosses dozens of alert thresholds → Slack/Teams/PagerDuty flood → alert fatigue → people start ignoring real alerts. |
| **Broken Dashboards** | Graphs show vertical spikes to infinity, zoom levels break, auto-scaling Y-axis becomes useless, heatmaps get dominated by one bad reading. Executives/SREs/customers lose trust immediately. |

### Real-World Examples of This Protection

| System | Why Clamping is Needed |
|--------|----------------------|
| **Container Orchestrators** (Kubernetes, Docker) | `/proc` or cgroup stats sometimes "jump" massively due to racing counters or collection glitches |
| **Disk Usage** (`df`/`du`) | Filesystems occasionally report nonsense during fsck, snapshot operations, or NFS weirdness |
| **Network Counters** (SNMP, Prometheus) | Cumulative counters can glitch producing negative deltas or huge positive jumps |
| **Cloud Provider Metering** (AWS, GCP, Azure) | Reject/cap implausible deltas to avoid billing disputes or broken cost allocation |
| **Energy/IoT Meters** | Cumulative Wh counters sometimes wrap around or glitch → cap to realistic max power × time |

### Statistical Impact Example

Consider a dataset of typical 20MB deltas:

```
Without clamping:  [20, 18, 22, 19, 4500, 21, 20]  → mean = 660MB (33x inflated)
With clamping:     [20, 18, 22, 19, 100, 21, 20]   → mean = 31MB  (realistic)
```

The single 4.5GB glitch would:
- Inflate the mean by **33x**
- Trigger capacity alerts for weeks
- Cause over-provisioning decisions costing thousands of dollars

---

## Task 1: Embedding Endpoint Selection

### Why sentence-transformers/all-MiniLM-L6-v2?

| Factor | Decision |
|--------|----------|
| **Dimension** | 384 (compact, fast) vs 768 (more accurate but slower) |
| **Latency** | ~150-200ms per request (acceptable for CLI) |
| **Quality** | Strong performance on semantic similarity benchmarks |
| **Cost** | Free tier available on HuggingFace |

### Cosine Similarity Implementation

Standard formula: `cos(θ) = (A · B) / (||A|| × ||B||)`

- Handles edge cases (zero vectors return 0.0)
- Validates dimension match before computation
- Returns normalized score between -1 and 1
