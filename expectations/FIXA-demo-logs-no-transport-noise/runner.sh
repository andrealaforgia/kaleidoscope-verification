#!/usr/bin/env bash
# FIX-A — after the generator runs, the logs query returns ONLY the demo's
# application log(s), with ZERO transport noise. Sprint item FIX-A (PO robust
# gate primary; deterministic count==1 secondary).
#
# Run the first-party generator against a live runtime, then query the
# UNFILTERED :9091 /api/v1/logs:
#   - the application log 'checkout failed: card declined' is present.
#   - ZERO records are transport noise (no body like 'encoding SETTINGS' /
#     'poll_ready' / h2 / hyper / tonic / tower / rustls chatter).
#   - secondary: the total record count is exactly 1.
#
# Transition-proof: RED now (the generator's gRPC client transport events are
# bridged to logs -> ~219 records), GREEN when only the application log remains.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"
SNAP="$HARNESS_DIR/.snapshot"
cp "$HARNESS_DIR/Dockerfile.kaleidoscope-runtime" "$SNAP/" 2>/dev/null || true
cp "$HARNESS_DIR/Dockerfile.kaleidoscope-telemetrygen" "$SNAP/" 2>/dev/null || true
docker build -q -t kx-runtime:crgen -f "$SNAP/Dockerfile.kaleidoscope-runtime" "$SNAP" > "$EVIDENCE_DIR/build.runtime.txt" 2>&1
docker build -q -t kx-gen:crgen -f "$SNAP/Dockerfile.kaleidoscope-telemetrygen" "$SNAP" > "$EVIDENCE_DIR/build.gen.txt" 2>&1

NET="fixa-net-$$"; RT="fixa-rt-$$"
cleanup() { docker stop "$RT" >/dev/null 2>&1 || true; docker rm "$RT" >/dev/null 2>&1 || true; docker network rm "$NET" >/dev/null 2>&1 || true; }
trap cleanup EXIT
docker network create "$NET" >/dev/null
docker run -d --name "$RT" --network "$NET" -e KALEIDOSCOPE_TENANT=acme -e RUST_LOG=warn -p 19490:9090 -p 19491:9091 kx-runtime:crgen > /dev/null
S=$(( $(date -u +%s) - 300 )); E=$(( $(date -u +%s) + 300 ))
for _ in $(seq 1 40); do [ "$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:19490/api/v1/query_range?query=request_count&start=${S}&end=${E}&step=15s" 2>/dev/null)" = "200" ] && { R=ok; break; }; sleep 1; done
[ "${R:-}" = ok ] || { echo "runtime never ready" >&2; docker logs "$RT" >&2 || true; exit 1; }
docker run --rm --network "$NET" -e OTEL_EXPORTER_OTLP_ENDPOINT="http://$RT:4317" -e KALEIDOSCOPE_TENANT=acme kx-gen:crgen > "$EVIDENCE_DIR/gen.out" 2> "$EVIDENCE_DIR/gen.err" || { echo "generator failed" >&2; cat "$EVIDENCE_DIR/gen.err" >&2; exit 1; }
sleep 2
curl -s -o "$EVIDENCE_DIR/logs.json" "http://localhost:19491/api/v1/logs?start=${S}&end=${E}"

python3 - "$EVIDENCE_DIR/logs.json" <<'PY'
import json, re, sys
logs = json.load(open(sys.argv[1]))
logs = logs if isinstance(logs, list) else []
total = len(logs)
app = [l for l in logs if "card declined" in str(l.get("body", ""))]
noise_re = re.compile(r"encoding SETTINGS|poll_ready|WINDOW_UPDATE|send frame|received frame|h2::|hyper::|tonic::|tower::|rustls|Connection|SETTINGS|PING", re.I)
noise = [l for l in logs if noise_re.search(str(l.get("body", "")))]
print(f"total_logs={total} app_logs={len(app)} noise_logs={len(noise)}")
sample = [str(l.get("body",""))[:60] for l in noise[:3]]
print("noise_sample=" + repr(sample))
fail = []
if len(app) < 1:
    fail.append("application log 'card declined' missing")
if len(noise) != 0:
    fail.append(f"{len(noise)} transport-noise records present (must be 0)")
if total != 1:
    fail.append(f"total log count is {total}, expected exactly 1 (secondary)")
if fail:
    print("FAIL: " + "; ".join(fail)); sys.exit(1)
print("FIXA satisfied — after the generator, :9091 returns only the application log (card declined), zero transport noise, count 1.")
PY
