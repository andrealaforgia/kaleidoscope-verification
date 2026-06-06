#!/usr/bin/env bash
# K32 — two tenants ingested into the SAME data dir stay isolated on
# read: `read acme` returns only acme's records, never globex's. Covers
# UC-CLI-009 (tenant isolation on the same data dir).
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
echo "{\"observed_time_unix_nano\":1700000000000000000,\"severity_number\":9,\"severity_text\":\"INFO\",\"body\":\"acme-rec\",\"attributes\":{},\"resource_attributes\":{},\"trace_id\":null,\"span_id\":null}" \
  | docker run --rm -i -v "$DATA_HOST:/data" "$KCLI_IMAGE" ingest acme /data >/dev/null 2>&1
echo "{\"observed_time_unix_nano\":1700000000000000000,\"severity_number\":9,\"severity_text\":\"INFO\",\"body\":\"globex-rec\",\"attributes\":{},\"resource_attributes\":{},\"trace_id\":null,\"span_id\":null}" \
  | docker run --rm -i -v "$DATA_HOST:/data" "$KCLI_IMAGE" ingest globex /data >/dev/null 2>&1
docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" read acme   /data > /tmp/acme.out   2>/dev/null
docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" read globex /data > /tmp/globex.out 2>/dev/null
echo "---acme---";   jq -r .body /tmp/acme.out   | tr "\n" " "; echo
echo "---globex---"; jq -r .body /tmp/globex.out | tr "\n" " "; echo
cp /tmp/acme.out "'"$EVIDENCE_DIR"'/acme.out"; cp /tmp/globex.out "'"$EVIDENCE_DIR"'/globex.out"
'
"$HARNESS_DIR/run-kaleidoscope-cli.sh" "$EVIDENCE_DIR" K32 "$INLINE"

A=$(jq -r .body "$EVIDENCE_DIR/acme.out"   | sort | tr '\n' ' ')
G=$(jq -r .body "$EVIDENCE_DIR/globex.out" | sort | tr '\n' ' ')
[[ "$A" == "acme-rec " ]]   || { echo "read acme returned unexpected bodies: $A (leak?)" >&2; exit 1; }
[[ "$G" == "globex-rec " ]] || { echo "read globex returned unexpected bodies: $G (leak?)" >&2; exit 1; }
echo "OK — tenants on the same data dir are isolated on read (acme sees only acme, globex only globex)"
