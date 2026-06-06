#!/usr/bin/env bash
# K26 — `read` honours the documented half-open `[since, until)` window:
# a record exactly at `--since` is INCLUDED, a record exactly at
# `--until` is EXCLUDED, and no flags returns the full range. Covers
# UC-RANGE-002 (half-open semantics) and UC-RANGE-003 (default = all).
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
IN=/tmp/in.ndjson
cat > "$IN" <<JSON
{"observed_time_unix_nano":1700000000000000000,"severity_number":9,"severity_text":"INFO","body":"t0","attributes":{},"resource_attributes":{},"trace_id":null,"span_id":null}
{"observed_time_unix_nano":1700000060000000000,"severity_number":9,"severity_text":"INFO","body":"t60","attributes":{},"resource_attributes":{},"trace_id":null,"span_id":null}
JSON
docker run --rm -i -v "$DATA_HOST:/data" "$KCLI_IMAGE" ingest acme /data < "$IN" >/dev/null 2>&1

# Default (no flags) -> both records.
docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" read acme /data \
    > /tmp/all.out 2>/dev/null
echo "default: $(jq -r .body /tmp/all.out | tr "\n" " ")"
cp /tmp/all.out "'"$EVIDENCE_DIR"'/default.out"

# --since exactly t0 -> INCLUDES t0 (since is inclusive).
docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" read acme /data \
    --since 2023-11-14T22:13:20Z > /tmp/since.out 2>/dev/null
echo "since-t0: $(jq -r .body /tmp/since.out | tr "\n" " ")"
cp /tmp/since.out "'"$EVIDENCE_DIR"'/since-t0.out"

# --until exactly t60 -> EXCLUDES t60 (until is exclusive: half-open).
docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" read acme /data \
    --until 2023-11-14T22:14:20Z > /tmp/until.out 2>/dev/null
echo "until-t60: $(jq -r .body /tmp/until.out | tr "\n" " ")"
cp /tmp/until.out "'"$EVIDENCE_DIR"'/until-t60.out"
'
"$HARNESS_DIR/run-kaleidoscope-cli.sh" "$EVIDENCE_DIR" K26 "$INLINE"

b() { jq -r .body "$1" | tr '\n' ' '; }
[[ "$(b "$EVIDENCE_DIR/default.out")"  == "t0 t60 " ]] || { echo "default range did not return all records" >&2; exit 1; }
[[ "$(b "$EVIDENCE_DIR/since-t0.out")" == "t0 t60 " ]] || { echo "--since at t0 should include t0 (inclusive)" >&2; exit 1; }
[[ "$(b "$EVIDENCE_DIR/until-t60.out")" == "t0 " ]]    || { echo "--until at t60 should EXCLUDE t60 (half-open)" >&2; exit 1; }
echo "OK — [since, until) is half-open: since inclusive, until exclusive; default = all"
