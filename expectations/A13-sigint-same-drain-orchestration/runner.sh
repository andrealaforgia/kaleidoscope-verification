#!/usr/bin/env bash
# A13 — SIGINT triggers the same drain orchestration as SIGTERM
# (slice 08). Same shape as A12; the only difference is the signal.

set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

CONTAINER="kaleidoscope-expectations-aperture-1"

echo "step 1: confirm aperture ready"
DEADLINE=$(( SECONDS + 30 ))
while (( SECONDS < DEADLINE )); do
    code="$(curl -sS --max-time 2 -o /dev/null -w '%{http_code}' \
                 http://localhost:4318/readyz 2>/dev/null || echo "")"
    [[ "$code" == "200" ]] && break
    sleep 1
done
[[ "${code:-}" == "200" ]] || { echo "aperture never became ready" >&2; exit 1; }

echo "step 2: send SIGINT"
( cd "$HARNESS_DIR" && docker compose kill -s SIGINT aperture >/dev/null 2>&1 )

echo "step 3: wait for container to exit (≤ 35 s)"
DEADLINE=$(( SECONDS + 35 ))
EXIT_CODE=""
while (( SECONDS < DEADLINE )); do
    state="$(docker inspect -f '{{.State.Status}}' "$CONTAINER" 2>/dev/null || echo "")"
    if [[ "$state" == "exited" ]]; then
        EXIT_CODE="$(docker inspect -f '{{.State.ExitCode}}' "$CONTAINER")"
        break
    fi
    sleep 0.5
done

if [[ -z "$EXIT_CODE" ]]; then
    echo "aperture container never reached 'exited' state" >&2
    exit 1
fi

printf '%s\n' "$EXIT_CODE" > "$EVIDENCE_DIR/aperture.exit-code.txt"
echo "  aperture exited with code: ${EXIT_CODE}"

( cd "$HARNESS_DIR" && docker compose logs --no-color aperture ) \
    > "$EVIDENCE_DIR/aperture.live.stderr.txt"

echo "  aperture stderr (last 6 events):"
grep -E '"event"' "$EVIDENCE_DIR/aperture.live.stderr.txt" | tail -6 | sed 's/^/    /'

if [[ "$EXIT_CODE" != "0" ]]; then
    echo "expected exit 0 after SIGINT, got ${EXIT_CODE}" >&2
    exit 1
fi
if ! grep -qE 'shutdown_initiated|drain_complete|drain' "$EVIDENCE_DIR/aperture.live.stderr.txt"; then
    echo "aperture stderr lacks any drain/shutdown event after SIGINT" >&2
    exit 1
fi

echo "OK — aperture exited 0 after SIGINT, same drain orchestration as SIGTERM (A12)"
