#!/usr/bin/env bash
# K01 — `kaleidoscope-cli --help` exits 0 and prints a usage banner naming the two subcommands.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
EC=0
docker run --rm "$KCLI_IMAGE" --help > /tmp/help.out 2>&1 || EC=$?
echo "exit=$EC"
echo "---help head---"
head -20 /tmp/help.out
cp /tmp/help.out "'"$EVIDENCE_DIR"'/help-output.txt"
'
"$HARNESS_DIR/run-kaleidoscope-cli.sh" "$EVIDENCE_DIR" K01 "$INLINE"

EC=$(grep -oE 'exit=[0-9]+' "$EVIDENCE_DIR/K01.stdout.txt" | tail -1 | cut -d= -f2)
echo "  kaleidoscope-cli --help exit: $EC"
[[ "$EC" == "0" ]] || { echo "expected 0" >&2; exit 1; }
grep -q "ingest" "$EVIDENCE_DIR/help-output.txt" || { echo "usage lacks 'ingest'" >&2; exit 1; }
grep -q "read"   "$EVIDENCE_DIR/help-output.txt" || { echo "usage lacks 'read'"   >&2; exit 1; }
echo "OK — --help exits 0 and prints usage naming both subcommands"
