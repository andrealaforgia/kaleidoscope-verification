#!/usr/bin/env bash
# G05 — the gateway drains gracefully and exits 0 on SIGTERM
# (UC-GWLIFE-004) and runs the same drain path on SIGINT (UC-GWLIFE-005).
# The gateway analogue of aperture's A11-A13.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
boot() { # $1=name
    # NOT --rm: we inspect the exit code AFTER the container stops, and
    # --rm would auto-remove it before we can read it.
    docker run -d --name "$1" -v "$DATA_HOST:/data" \
        -e KALEIDOSCOPE_DEFAULT_TENANT=acme -e RUST_LOG=info "$GW_IMAGE" > /dev/null
    for i in $(seq 1 30); do docker logs "$1" 2>&1 | grep -q listener_bound && return 0; sleep 0.5; done
    echo "gateway $1 never bound" >&2; return 1
}

# SIGTERM (docker stop sends SIGTERM, then SIGKILL after the grace
# period; a clean drain exits 0 well within it).
NT="g05-term-$$"; boot "$NT" || exit 1
docker stop --time 15 "$NT" >/dev/null 2>&1 || true
echo "sigterm_exit=$(docker inspect -f "{{.State.ExitCode}}" "$NT" 2>/dev/null || echo NA)"
docker logs "$NT" > "'"$EVIDENCE_DIR"'/sigterm.stderr.txt" 2>&1 || true
docker rm -f "$NT" >/dev/null 2>&1 || true

# SIGINT (explicit signal).
NI="g05-int-$$"; boot "$NI" || exit 1
docker kill -s INT "$NI" >/dev/null 2>&1 || true
for i in $(seq 1 20); do [[ "$(docker inspect -f "{{.State.Running}}" "$NI" 2>/dev/null)" == "false" ]] && break; sleep 0.5; done
echo "sigint_exit=$(docker inspect -f "{{.State.ExitCode}}" "$NI" 2>/dev/null || echo NA)"
echo "sigint_running=$(docker inspect -f "{{.State.Running}}" "$NI" 2>/dev/null || echo NA)"
docker logs "$NI" > "'"$EVIDENCE_DIR"'/sigint.stderr.txt" 2>&1 || true
docker rm -f "$NI" >/dev/null 2>&1 || true
'
"$HARNESS_DIR/run-gateway.sh" "$EVIDENCE_DIR" G05 "$INLINE"

OUT="$EVIDENCE_DIR/G05.stdout.txt"
val() { grep -oE "$1=[^ ]+" "$OUT" | tail -1 | cut -d= -f2; }
[[ "$(val sigterm_exit)" == "0" ]]    || { echo "SIGTERM did not exit 0 (got $(val sigterm_exit))" >&2; exit 1; }
[[ "$(val sigint_exit)"  == "0" ]]    || { echo "SIGINT did not exit 0 (got $(val sigint_exit))" >&2; exit 1; }
[[ "$(val sigint_running)" == "false" ]] || { echo "SIGINT did not stop the gateway" >&2; exit 1; }
echo "OK — gateway drains and exits 0 on SIGTERM, and runs the same drain to exit 0 on SIGINT"
