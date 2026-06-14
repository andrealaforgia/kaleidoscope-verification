#!/usr/bin/env bash
# FIXB2 — the three query APIs accept RFC3339 timestamps (not only
# unix-seconds), and an unparseable timestamp returns a 400 whose message NAMES
# both accepted formats (not the bare "is not a number"). Sprint item FIX-B.2;
# the parser is centralised in query_http_common::parse_time_range so all three
# APIs share the behaviour.
#
# Probes one runtime on each of :9090 (metrics) / :9091 (logs) / :9092 (traces):
#   - start/end as unix-seconds        -> 200 (baseline, works today)
#   - start/end as RFC3339 (..T..Z)    -> 200 (the fix; RED today: 400)
#   - start/end unparseable            -> 400 whose body names BOTH RFC3339 and
#                                         unix-seconds (RED today: "is not a number")
#
# Transition-proof: RED now (RFC3339 -> 400 "start is not a number"), flips
# GREEN when parse_time_range accepts RFC3339 + the error message names both
# formats.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

# RFC3339 window (5 min) + its exact unix-seconds equivalent.
RFC_START="2026-06-14T00:00:00Z"; RFC_END="2026-06-14T00:05:00Z"
U_START=$(python3 -c "import datetime;print(int(datetime.datetime.fromisoformat('2026-06-14T00:00:00+00:00').timestamp()))")
U_END=$(python3 -c "import datetime;print(int(datetime.datetime.fromisoformat('2026-06-14T00:05:00+00:00').timestamp()))")
export RFC_START RFC_END U_START U_END

INLINE='
RT="fixb2-rt-$$"
cleanup() { docker stop "$RT" >/dev/null 2>&1 || true; docker rm "$RT" >/dev/null 2>&1 || true; }
trap cleanup EXIT
docker run -d --name "$RT" -e KALEIDOSCOPE_TENANT=acme -e RUST_LOG=warn \
    -p 19170:9090 -p 19171:9091 -p 19172:9092 "$CRT_IMAGE" > /dev/null
RNOW=$(date -u +%s)
for _ in $(seq 1 40); do
    [ "$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:19170/api/v1/query_range?query=request_count&start=$((RNOW-300))&end=${RNOW}&step=15s" 2>/dev/null)" = "200" ] && { R=ok; break; }
    sleep 1
done
[ "${R:-}" = ok ] || { echo "runtime never ready" >&2; docker logs "$RT" >&2 || true; exit 1; }

# base URLs (params appended per probe). traces needs service=; logs/metrics not.
probe() { # $1 label  $2 full-url  $3 outfile
    echo "$1=$(curl -s -o "$3" -w "%{http_code}" "$2")"
}
M="http://localhost:19170/api/v1/query_range?query=request_count&step=15s"
L="http://localhost:19171/api/v1/logs"
T="http://localhost:19172/api/v1/traces?service=svc"
E="'"$EVIDENCE_DIR"'"

# metrics
probe m_unix "${M}&start='"$U_START"'&end='"$U_END"'" "$E/m_unix.json"
probe m_rfc  "${M}&start='"$RFC_START"'&end='"$RFC_END"'" "$E/m_rfc.json"
probe m_bad  "${M}&start=notatime&end='"$U_END"'" "$E/m_bad.json"
# logs
probe l_unix "${L}?start='"$U_START"'&end='"$U_END"'" "$E/l_unix.json"
probe l_rfc  "${L}?start='"$RFC_START"'&end='"$RFC_END"'" "$E/l_rfc.json"
probe l_bad  "${L}?start=notatime&end='"$U_END"'" "$E/l_bad.json"
# traces
probe t_unix "${T}&start='"$U_START"'&end='"$U_END"'" "$E/t_unix.json"
probe t_rfc  "${T}&start='"$RFC_START"'&end='"$RFC_END"'" "$E/t_rfc.json"
probe t_bad  "${T}&start=notatime&end='"$U_END"'" "$E/t_bad.json"
'
"$HARNESS_DIR/run-kaleidoscope-runtime.sh" "$EVIDENCE_DIR" FIXB2 "$INLINE"

OUT="$EVIDENCE_DIR/FIXB2.stdout.txt"
code() { grep -oE "$1=[0-9]+" "$OUT" | tail -1 | cut -d= -f2; }
fail() { echo "FAIL: $1" >&2; cat "$OUT" >&2; exit 1; }
names_both() { # $1 body file -> 0 if the 400 names both RFC3339 and unix-seconds
    grep -qiE 'rfc.?3339|[0-9]{4}-[0-9]{2}-[0-9]{2}t' "$1" 2>/dev/null && grep -qiE 'unix|seconds|epoch' "$1" 2>/dev/null
}

for api in m l t; do
    [ "$(code ${api}_unix)" = "200" ] || fail "${api}: unix-seconds window not 200 (got $(code ${api}_unix)) — baseline broken"
    [ "$(code ${api}_rfc)" = "200" ] || fail "${api}: RFC3339 window not accepted (got $(code ${api}_rfc), expected 200) — FIX-B.2 not delivered on this API"
    [ "$(code ${api}_bad)" = "400" ] || fail "${api}: unparseable timestamp not 400 (got $(code ${api}_bad))"
    names_both "$EVIDENCE_DIR/${api}_bad.json" || fail "${api}: the 400 message does not name BOTH formats (RFC3339 + unix-seconds). Body: $(cat "$EVIDENCE_DIR/${api}_bad.json")"
done

echo "FIXB2 satisfied — all three query APIs (:9090/:9091/:9092) accept RFC3339 AND unix-seconds (200), and an unparseable timestamp returns 400 naming both formats."
