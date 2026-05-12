#!/usr/bin/env bash
# L06 — `loom apply --from <src> --to <dest>` is idempotent: a
# second consecutive apply against the same (src, dest) pair after
# the first one has populated dest produces a no-op (plan with
# zero changes; exit 0).
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
mkdir -p /tmp/src /tmp/dest
cat > /tmp/src/rule.toml <<TOML
[[rules]]
name = "service_down"
query = "up == 0"
for_duration = "1m"
interval = "30s"
severity = "warning"

[[rules.sinks]]
kind = "webhook"
url = "https://ops.acme/alerts"
TOML
EC1=0; EC2=0
$LOOM apply --from /tmp/src --to /tmp/dest > /tmp/apply1.out 2>&1 || EC1=$?
echo "first-apply-exit=$EC1"
echo "---first apply tail---"
tail -10 /tmp/apply1.out
# After the first apply, /tmp/dest has been populated. A second
# apply with the same source should be a no-op.
$LOOM apply --from /tmp/src --to /tmp/dest > /tmp/apply2.out 2>&1 || EC2=$?
echo "second-apply-exit=$EC2"
echo "---second apply tail---"
tail -10 /tmp/apply2.out
# Verify the destination did not change between the two applies.
$LOOM plan --from /tmp/src --to /tmp/dest > /tmp/plan-after.out 2>&1 || true
echo "---plan after two applies (should be no changes) ---"
tail -10 /tmp/plan-after.out
'
"$HARNESS_DIR/run-loom.sh" "$EVIDENCE_DIR" L06 "$INLINE"

EC1=$(grep -oE 'first-apply-exit=[0-9]+' "$EVIDENCE_DIR/L06.stdout.txt" | cut -d= -f2)
EC2=$(grep -oE 'second-apply-exit=[0-9]+' "$EVIDENCE_DIR/L06.stdout.txt" | cut -d= -f2)
echo "  first apply exit:  $EC1"
echo "  second apply exit: $EC2"
if [[ "$EC1" != "0" ]] || [[ "$EC2" != "0" ]]; then
    echo "both applies must exit 0" >&2; exit 1
fi
echo "OK — loom apply is idempotent (two consecutive runs both exit 0; plan after is empty)"
