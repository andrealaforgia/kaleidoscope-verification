#!/usr/bin/env bash
# K34 — the Cinder tiering commands emit an OTLP-JSON audit trail via
# --observe-otlp:
#   - migrate appends one `cinder.migrate.count` line carrying from/to
#     tier attributes (UC-CLIOBS-003);
#   - evaluate-policy appends one line PER migration it performs
#     (UC-CLIOBS-004);
#   - the observation file is append-only across runs — a second command
#     writing the same file keeps the first run's lines (UC-CLIOBS-005).
# Every line carries the tenant_id resource attribute (UC-CLIOBS-007).
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
run() { docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" "$@"; }
# Audit trail for manual migrate (append twice to the same file).
run place acme /data p1 hot >/dev/null 2>&1
run migrate acme /data p1 warm --observe-otlp /data/obs.ndjson >/dev/null 2>&1
run migrate acme /data p1 cold --observe-otlp /data/obs.ndjson >/dev/null 2>&1
cp "$DATA_HOST/obs.ndjson" "'"$EVIDENCE_DIR"'/obs.ndjson"
# Audit trail for evaluate-policy: two fresh hot items -> two migrations.
run place acme /data e1 hot >/dev/null 2>&1
run place acme /data e2 hot >/dev/null 2>&1
run evaluate-policy /data 0 0 --observe-otlp /data/evobs.ndjson >/dev/null 2>&1
cp "$DATA_HOST/evobs.ndjson" "'"$EVIDENCE_DIR"'/evobs.ndjson"
'
"$HARNESS_DIR/run-kaleidoscope-cli.sh" "$EVIDENCE_DIR" K34 "$INLINE"

OBS="$EVIDENCE_DIR/obs.ndjson"; EV="$EVIDENCE_DIR/evobs.ndjson"
name()   { jq -r '.scopeMetrics[0].metrics[0].name' ; }
attr()   { jq -r --arg k "$1" '.scopeMetrics[0].metrics[0].sum.dataPoints[0].attributes[] | select(.key==$k) | .value.stringValue'; }

# UC-CLIOBS-005: append-only — two migrate runs => two lines.
[[ "$(wc -l < "$OBS")" -eq 2 ]] || { echo "obs file is not append-only (expected 2 lines, got $(wc -l < "$OBS"))" >&2; exit 1; }
# Both lines are cinder.migrate.count.
[[ "$(name < "$OBS" | sort -u)" == "cinder.migrate.count" ]] || { echo "obs lines are not all cinder.migrate.count" >&2; exit 1; }
# UC-CLIOBS-003: the first migrate line carries from=hot to=warm; tenant_id present.
[[ "$(sed -n '1p' "$OBS" | attr from)" == "hot" ]]  || { echo "first migrate line missing from=hot" >&2; exit 1; }
[[ "$(sed -n '1p' "$OBS" | attr to)"   == "warm" ]] || { echo "first migrate line missing to=warm" >&2; exit 1; }
[[ "$(sed -n '1p' "$OBS" | attr tenant_id)" == "acme" ]] || { echo "migrate line missing tenant_id=acme (UC-CLIOBS-007)" >&2; exit 1; }
# The second line is the warm->cold migration (append preserved both).
[[ "$(sed -n '2p' "$OBS" | attr to)" == "cold" ]] || { echo "second migrate line missing to=cold (append lost it?)" >&2; exit 1; }
# UC-CLIOBS-004: evaluate-policy emits one cinder.migrate.count line PER
# migration (2 hot items -> 2), plus a cinder.evaluate.migrated.count
# summary carrying the total (asInt=2).
MIG_LINES=$(name < "$EV" | grep -c '^cinder\.migrate\.count$')
[[ "$MIG_LINES" -eq 2 ]] || { echo "evaluate-policy did not emit one cinder.migrate.count per migration (expected 2, got $MIG_LINES)" >&2; exit 1; }
SUMMARY=$(jq -r 'select(.scopeMetrics[0].metrics[0].name=="cinder.evaluate.migrated.count") | .scopeMetrics[0].metrics[0].sum.dataPoints[0].asInt' "$EV" | tail -1)
[[ "$SUMMARY" == "2" ]] || { echo "evaluate-policy summary cinder.evaluate.migrated.count != 2 (got $SUMMARY)" >&2; exit 1; }
echo "OK — migrate appends cinder.migrate.count with from/to + tenant_id; evaluate-policy emits one cinder.migrate.count per migration plus a migrated=2 summary; the observation file is append-only"
