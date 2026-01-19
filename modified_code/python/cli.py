import os, time, json, math, click, requests
from dotenv import load_dotenv
load_dotenv()

API_KEY = os.getenv("API_KEY", "")
ENDPOINT_URL = os.getenv("ENDPOINT_URL", "")

def _json_print(obj):
    print(json.dumps(obj, indent=2))

def cosine_sim(a, b):
    # a and b are lists of floats
    dot = sum(x*y for x, y in zip(a, b))
    na = math.sqrt(sum(x*x for x in a))
    nb = math.sqrt(sum(y*y for y in b))
    if na == 0 or nb == 0:
        return 0.0
    return dot / (na * nb)

def compute_safe_delta(prev, curr):
    """Return a sane delta, correcting anomalies."""
    MAX_DELTA = 100 * 1024 * 1024  # 100MB
    if curr < prev:
        return 0
    delta = curr - prev
    if delta > MAX_DELTA:
        return MAX_DELTA
    return delta

@click.group()
def cli():
    pass

@cli.command()
@click.option("--text", required=True, help="Input text (prompt or 'docA|docB' for embeddings)")
@click.option("--task", required=True, type=click.Choice(["infer","embed"]))
def run(task, text):
    t0 = time.time()

    headers = {"Content-Type": "application/json"}
    if API_KEY:
        headers["Authorization"] = f"Bearer {API_KEY}"

    try:
        if task == "embed":
            # Expect an embeddings endpoint that returns {"embeddings": [..vector..]}
            if '|' not in text:
                _json_print({"status": 400, "error": "Invalid input: expected 'docA|docB'"})
                return

            docA, docB = text.split('|', 1)
            embA = _fetch_embedding(docA.strip(), headers)
            embB = _fetch_embedding(docB.strip(), headers)
            latency_ms = int((time.time() - t0) * 1000)
            sim = cosine_sim(embA, embB)

            _json_print({
                "status": 200,
                "latency_ms": latency_ms,
                "vector_dim": len(embA),
                "similarity_score": round(sim, 6)
            })
        else:
            # Basic inference passthrough
            payload = {"inputs": f"infer: {text}"}
            r = requests.post(ENDPOINT_URL, headers=headers, data=json.dumps(payload), timeout=60)
            latency_ms = int((time.time() - t0) * 1000)
            _json_print({"status": r.status_code, "latency_ms": latency_ms, "output": r.text[:240]})
    except requests.Timeout:
        _json_print({"status": 504, "error": "Request timed out"})
    except Exception as e:
        _json_print({"status": 500, "error": str(e)})

def _fetch_embedding(text, headers):
    payload = {"inputs": text}
    r = requests.post(ENDPOINT_URL, headers=headers, data=json.dumps(payload), timeout=60)
    if r.status_code >= 400:
        raise RuntimeError(f"Embedding request failed: {r.status_code} {r.text[:160]}" )
    data = r.json()
    # Accept either {"embeddings": [...]} or raw vector [...]
    if isinstance(data, dict) and "embeddings" in data:
        return [float(x) for x in data["embeddings"]]
    if isinstance(data, list):
        return [float(x) for x in data]
    raise RuntimeError("Unexpected embedding response format")

if __name__ == "__main__":
    cli()
