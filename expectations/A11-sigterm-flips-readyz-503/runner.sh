#!/usr/bin/env bash
# A11 — On SIGTERM, /readyz flips to 503.
#
# Source-feed wording was "circa 100 ms"; the catalogue tightened it to
# "before the drain completes" since no ADR pins a hard millisecond
# bound. Slice 08 contract: the readiness state machine flips to
# `Draining` before the drain orchestrator closes listeners; the
# aperture stderr emits `event=readiness_changed reason=draining`
# (or similar) at the moment of the flip.

set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

URL="http://localhost:4318/readyz"

echo "step 1: confirm /readyz=200 with aperture healthy"
DEADLINE=$(( SECONDS + 30 ))
while (( SECONDS < DEADLINE )); do
    code="$(curl -sS --max-time 2 -o /dev/null -w '%{http_code}' "$URL" 2>/dev/null || echo "")"
    [[ "$code" == "200" ]] && break
    sleep 1
done
[[ "${code:-}" == "200" ]] || { echo "aperture never became ready" >&2; exit 1; }
echo "  /readyz=200"

echo "step 2: send SIGTERM to aperture container"
( cd "$HARNESS_DIR" && docker compose kill -s SIGTERM aperture >/dev/null 2>&1 )

# Poll /readyz: it should go from 200 to 503 quickly. Capture the
# transition.
echo "step 3: poll /readyz for 503 within 5 s"
SIGTERM_AT=$SECONDS
DEADLINE=$(( SECONDS + 5 ))
TRANSITION_CODE=""
TRANSITION_BODY=""
ELAPSED_MS=""
attempts=0
while (( SECONDS < DEADLINE )); do
    attempts=$((attempts + 1))
    body_file="$EVIDENCE_DIR/readyz.${attempts}.body.txt"
    code="$(curl -sS --max-time 1 -o "$body_file" -w '%{http_code}' "$URL" 2>/dev/null || echo "curl-failed")"
    elapsed_ms=$(( (SECONDS - SIGTERM_AT) * 1000 ))
    echo "  attempt ${attempts} +${elapsed_ms}ms: code=${code}"
    if [[ "$code" == "503" ]]; then
        TRANSITION_CODE="$code"
        TRANSITION_BODY="$(cat "$body_file" 2>/dev/null || true)"
        ELAPSED_MS="$elapsed_ms"
        break
    fi
    if [[ "$code" == "curl-failed" ]]; then
        # The HTTP listener may have closed already; that is also a
        # valid drain outcome but harder to assert as "503". Continue
        # polling for a short window to be sure.
        TRANSITION_CODE="curl-failed"
        TRANSITION_BODY="(connection refused — listener closed)"
        ELAPSED_MS="$elapsed_ms"
        break
    fi
    sleep 0.2
done

# 4. Capture aperture stderr now (before run-expectation.sh's own
#    capture, which happens after we exit).
( cd "$HARNESS_DIR" && docker compose logs --no-color aperture ) \
    > "$EVIDENCE_DIR/aperture.live.stderr.txt"

echo "step 4: assert"
echo "  observed code after SIGTERM: ${TRANSITION_CODE}"
echo "  elapsed since SIGTERM:       ${ELAPSED_MS}ms"
echo "  body:                        ${TRANSITION_BODY}"

if [[ "$TRANSITION_CODE" != "503" ]]; then
    echo "expected HTTP 503 from /readyz after SIGTERM (saw '${TRANSITION_CODE}')" >&2
    exit 1
fi

# Sanity-check aperture stderr emitted a readiness change event
# during the drain.
if ! grep -qE 'readiness_changed|drain|shutdown' "$EVIDENCE_DIR/aperture.live.stderr.txt"; then
    echo "aperture stderr lacks any readiness/drain/shutdown event" >&2
    exit 1
fi

echo "OK — /readyz flipped to 503 within ${ELAPSED_MS}ms of SIGTERM"
