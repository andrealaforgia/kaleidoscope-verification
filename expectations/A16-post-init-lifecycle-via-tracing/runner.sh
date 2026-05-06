#!/usr/bin/env bash
# A16 — Post-init, every lifecycle event is structured tracing on
# stderr. ADR-0009 lines 13, 25, 34 lock the contract:
#   - tracing-subscriber JSON layer to stderr,
#   - one event per line,
#   - level + timestamp + event-name field per line,
#   - flatten_event(true), with_target(false), with_current_span(false),
#     with_span_list(false).
#
# The source-feed wording said "target=\"aperture\"" — that contradicts
# `with_target(false)`. The catalogue trusts the ADR (committed,
# external) over the inter-session feed and asserts the ADR-shaped
# contract: every line is valid JSON with `timestamp`, `level`, and
# `event`; no `target` field; no `span` / `spans` field.

set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

echo "step 1: wait for aperture ready"
DEADLINE=$(( SECONDS + 30 ))
while (( SECONDS < DEADLINE )); do
    code="$(curl -sS --max-time 2 -o /dev/null -w '%{http_code}' \
                 http://localhost:4318/readyz 2>/dev/null || echo "")"
    [[ "$code" == "200" ]] && break
    sleep 1
done
[[ "${code:-}" == "200" ]] || { echo "aperture never became ready" >&2; exit 1; }

echo "step 2: snapshot aperture stderr"
( cd "$HARNESS_DIR" && docker compose logs --no-color --no-log-prefix aperture ) \
    > "$EVIDENCE_DIR/aperture.live.stderr.txt"

LINES_TOTAL=0
LINES_BAD_JSON=0
LINES_MISSING_FIELD=0
LINES_WITH_TARGET=0
LINES_WITH_SPAN=0

while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    LINES_TOTAL=$((LINES_TOTAL + 1))
    if ! jq -e . <<<"$line" >/dev/null 2>&1; then
        LINES_BAD_JSON=$((LINES_BAD_JSON + 1))
        continue
    fi
    if ! jq -e '. | (has("timestamp") and has("level") and has("event"))' <<<"$line" >/dev/null 2>&1; then
        LINES_MISSING_FIELD=$((LINES_MISSING_FIELD + 1))
    fi
    if jq -e '. | has("target")' <<<"$line" >/dev/null 2>&1; then
        LINES_WITH_TARGET=$((LINES_WITH_TARGET + 1))
    fi
    if jq -e '. | (has("span") or has("spans"))' <<<"$line" >/dev/null 2>&1; then
        LINES_WITH_SPAN=$((LINES_WITH_SPAN + 1))
    fi
done < "$EVIDENCE_DIR/aperture.live.stderr.txt"

REPORT="$EVIDENCE_DIR/json-shape-report.txt"
{
    echo "# json-shape-report"
    echo "kaleidoscope_sha:    $(cat "$EVIDENCE_DIR/verification.yaml" 2>/dev/null | sed -n 's/^kaleidoscope_sha: //p' | tr -d '"')"
    echo "lines_total:         ${LINES_TOTAL}"
    echo "lines_bad_json:      ${LINES_BAD_JSON}"
    echo "lines_missing_field: ${LINES_MISSING_FIELD}"
    echo "lines_with_target:   ${LINES_WITH_TARGET} (ADR-0009 with_target(false): expected 0)"
    echo "lines_with_span:     ${LINES_WITH_SPAN} (ADR-0009 with_current_span/with_span_list(false): expected 0)"
} > "$REPORT"
cat "$REPORT"

# Assertions: at least one line, all parse as JSON, all carry the
# three required fields, none carry `target` or `span` keys.
if (( LINES_TOTAL == 0 )); then
    echo "no aperture stderr lines captured" >&2
    exit 1
fi
if (( LINES_BAD_JSON > 0 )); then
    echo "${LINES_BAD_JSON} non-JSON line(s) on aperture stderr" >&2
    exit 1
fi
if (( LINES_MISSING_FIELD > 0 )); then
    echo "${LINES_MISSING_FIELD} line(s) missing timestamp/level/event field" >&2
    exit 1
fi
if (( LINES_WITH_TARGET > 0 )); then
    echo "${LINES_WITH_TARGET} line(s) carry a 'target' field; ADR-0009 sets with_target(false)" >&2
    exit 1
fi
if (( LINES_WITH_SPAN > 0 )); then
    echo "${LINES_WITH_SPAN} line(s) carry a 'span'/'spans' field; ADR-0009 sets with_current_span(false)/with_span_list(false)" >&2
    exit 1
fi

echo "OK — ${LINES_TOTAL} aperture stderr lines, all conforming to the ADR-0009 JSON shape"
