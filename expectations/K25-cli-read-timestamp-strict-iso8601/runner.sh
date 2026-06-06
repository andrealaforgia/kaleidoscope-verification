#!/usr/bin/env bash
# K25 — `read --since/--until` enforces strict canonical ISO-8601 UTC:
# fractional seconds (1-9 digits) are accepted and filter correctly,
# but lower-case `z` and the `+00:00` offset form are rejected with a
# non-zero exit and a precise position diagnostic. Covers UC-RANGE-008
# (fractional accepted), UC-RANGE-009 (lowercase z rejected),
# UC-RANGE-010 (+00:00 rejected).
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

# Fractional seconds accepted: --since .5s past t0 keeps only t60.
docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" read acme /data \
    --since 2023-11-14T22:13:20.500000000Z > /tmp/frac.out 2>/tmp/frac.err
echo "frac-exit=$?" > /tmp/frac.rc
echo "---fractional---"; cat /tmp/frac.rc; jq -r .body /tmp/frac.out 2>/dev/null | tr "\n" " "; echo
cp /tmp/frac.out "'"$EVIDENCE_DIR"'/fractional.out"; cp /tmp/frac.rc "'"$EVIDENCE_DIR"'/fractional.rc"

# Lower-case z rejected.
docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" read acme /data \
    --since 2023-11-14T22:13:20z > /tmp/lz.out 2>&1
echo "lz-exit=$?" > /tmp/lz.rc
echo "---lowercase z---"; cat /tmp/lz.rc; cat /tmp/lz.out
cp /tmp/lz.out "'"$EVIDENCE_DIR"'/lowercase-z.out"; cp /tmp/lz.rc "'"$EVIDENCE_DIR"'/lowercase-z.rc"

# +00:00 offset rejected.
docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" read acme /data \
    --since 2023-11-14T22:13:20+00:00 > /tmp/off.out 2>&1
echo "off-exit=$?" > /tmp/off.rc
echo "---+00:00---"; cat /tmp/off.rc; cat /tmp/off.out
cp /tmp/off.out "'"$EVIDENCE_DIR"'/offset.out"; cp /tmp/off.rc "'"$EVIDENCE_DIR"'/offset.rc"
'
"$HARNESS_DIR/run-kaleidoscope-cli.sh" "$EVIDENCE_DIR" K25 "$INLINE"

# Fractional: exit 0, filtered to t60 only.
grep -qx 'frac-exit=0' "$EVIDENCE_DIR/fractional.rc" || { echo "fractional --since did not parse (non-zero exit)" >&2; exit 1; }
[[ "$(jq -r .body "$EVIDENCE_DIR/fractional.out" | tr '\n' ' ')" == "t60 " ]] || { echo "fractional --since did not filter to t60" >&2; exit 1; }
# Lowercase z: rejected.
grep -qx 'lz-exit=0' "$EVIDENCE_DIR/lowercase-z.rc" && { echo "lowercase z was accepted (should be strict Z)" >&2; exit 1; }
grep -qF "expected 'Z', got 'z'" "$EVIDENCE_DIR/lowercase-z.out" || { echo "lowercase z lacked the strict-Z diagnostic" >&2; exit 1; }
# +00:00: rejected.
grep -qx 'off-exit=0' "$EVIDENCE_DIR/offset.rc" && { echo "+00:00 offset was accepted (should be canonical Z only)" >&2; exit 1; }
grep -qF "got '+'" "$EVIDENCE_DIR/offset.out" || { echo "+00:00 lacked the canonical-Z diagnostic" >&2; exit 1; }
echo "OK — fractional accepted+filters; lowercase z and +00:00 rejected with position diagnostics"
