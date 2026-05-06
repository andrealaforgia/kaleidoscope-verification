#!/usr/bin/env bash
# A12 — On SIGTERM, the drain orchestrator completes in-flight
# requests within drain_deadline_ms (default 30000) and aperture
# exits with code 0. With no in-flight load this collapses to "clean
# drain on SIGTERM"; A14 will exercise the deadline-exceeded branch
# once a slow-downstream harness lands.

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
echo "  /readyz=200"

echo "step 2: send SIGTERM"
( cd "$HARNESS_DIR" && docker compose kill -s SIGTERM aperture >/dev/null 2>&1 )

echo "step 3: wait for container to exit (≤ 35 s; default drain_deadline_ms is 30000)"
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
    docker inspect -f '{{.State.Status}} {{.State.ExitCode}}' "$CONTAINER" 2>&1 || true
    exit 1
fi

printf '%s\n' "$EXIT_CODE" > "$EVIDENCE_DIR/aperture.exit-code.txt"
echo "  aperture exited with code: ${EXIT_CODE}"

# Capture aperture's full stderr now (drain + shutdown lifecycle
# events are the body of evidence).
( cd "$HARNESS_DIR" && docker compose logs --no-color aperture ) \
    > "$EVIDENCE_DIR/aperture.live.stderr.txt"

echo "  aperture stderr (last 6 events):"
grep -E '"event"' "$EVIDENCE_DIR/aperture.live.stderr.txt" | tail -6 | sed 's/^/    /'

if [[ "$EXIT_CODE" != "0" ]]; then
    echo "expected exit 0 (clean drain), got ${EXIT_CODE}" >&2
    exit 1
fi

# Sanity: a drain/shutdown event should appear in stderr.
if ! grep -qE 'shutdown_initiated|drain_complete|drain' "$EVIDENCE_DIR/aperture.live.stderr.txt"; then
    echo "aperture stderr lacks any drain/shutdown event" >&2
    exit 1
fi

echo "OK — aperture exited 0 after SIGTERM with drain-related events emitted"
