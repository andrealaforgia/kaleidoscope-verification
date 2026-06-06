#!/usr/bin/env bash
# G04 — the gateway resolves its pillar root from a CLI positional arg
# (UC-GWLIFE-001) and from KALEIDOSCOPE_PILLAR_ROOT (UC-GWLIFE-002), and
# creates the pillars under the resolved root. The structured
# gateway_starting event reports the resolved pillar_root, and the
# durable pillar files appear under it.
#
# The harness image pins ENV KALEIDOSCOPE_PILLAR_ROOT=/data, so:
#   - the CLI positional must OVERRIDE that env (precedence), and
#   - an explicit env override must be honoured.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
# Case 1: CLI positional /data/cliroot (overrides the image env=/data).
NA="g04-cli-$$"
docker run --rm -d --name "$NA" -v "$DATA_HOST:/data" \
    -e KALEIDOSCOPE_DEFAULT_TENANT=acme -e RUST_LOG=info "$GW_IMAGE" /data/cliroot > /dev/null
for i in $(seq 1 30); do docker logs "$NA" 2>&1 | grep -q listener_bound && break; sleep 0.5; done
docker logs "$NA" > "'"$EVIDENCE_DIR"'/cli.stderr.txt" 2>&1 || true
docker exec "$NA" ls /data/cliroot > "'"$EVIDENCE_DIR"'/cli.pillars.txt" 2>&1 || true
docker stop --time 5 "$NA" >/dev/null 2>&1 || true

# Case 2: env KALEIDOSCOPE_PILLAR_ROOT=/data/envroot, no positional.
NB="g04-env-$$"
docker run --rm -d --name "$NB" -v "$DATA_HOST:/data" \
    -e KALEIDOSCOPE_DEFAULT_TENANT=acme -e KALEIDOSCOPE_PILLAR_ROOT=/data/envroot -e RUST_LOG=info "$GW_IMAGE" > /dev/null
for i in $(seq 1 30); do docker logs "$NB" 2>&1 | grep -q listener_bound && break; sleep 0.5; done
docker logs "$NB" > "'"$EVIDENCE_DIR"'/env.stderr.txt" 2>&1 || true
docker stop --time 5 "$NB" >/dev/null 2>&1 || true
'
"$HARNESS_DIR/run-gateway.sh" "$EVIDENCE_DIR" G04 "$INLINE"

pr() { grep -F '"event":"gateway_starting"' "$1" | head -1 | jq -r '.pillar_root // "MISSING"'; }
CLI_PR=$(pr "$EVIDENCE_DIR/cli.stderr.txt")
ENV_PR=$(pr "$EVIDENCE_DIR/env.stderr.txt")
[[ "$CLI_PR" == "/data/cliroot" ]] || { echo "CLI positional not honoured: pillar_root=$CLI_PR (expected /data/cliroot, overriding image env)" >&2; exit 1; }
[[ "$ENV_PR" == "/data/envroot" ]] || { echo "env KALEIDOSCOPE_PILLAR_ROOT not honoured: pillar_root=$ENV_PR" >&2; exit 1; }
# Pillars actually created under the CLI root.
grep -qE 'lumen\.snapshot' "$EVIDENCE_DIR/cli.pillars.txt" || { echo "no pillar files created under the CLI root" >&2; cat "$EVIDENCE_DIR/cli.pillars.txt" >&2; exit 1; }
echo "OK — CLI positional pillar root /data/cliroot honoured (overrides image env) with pillars created under it; KALEIDOSCOPE_PILLAR_ROOT=/data/envroot honoured"
