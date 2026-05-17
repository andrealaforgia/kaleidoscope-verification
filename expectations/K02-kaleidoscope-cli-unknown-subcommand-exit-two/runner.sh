#!/usr/bin/env bash
# K02 — Unknown subcommand exits 2 with a diagnostic on stderr.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
EC=0
docker run --rm "$KCLI_IMAGE" totally-bogus > /tmp/out.txt 2> /tmp/err.txt || EC=$?
echo "exit=$EC"
echo "---stderr head---"
head -5 /tmp/err.txt
cp /tmp/err.txt "'"$EVIDENCE_DIR"'/unknown-subcommand.stderr.txt"
'
"$HARNESS_DIR/run-kaleidoscope-cli.sh" "$EVIDENCE_DIR" K02 "$INLINE"

EC=$(grep -oE 'exit=[0-9]+' "$EVIDENCE_DIR/K02.stdout.txt" | tail -1 | cut -d= -f2)
echo "  exit code: $EC"
[[ "$EC" == "2" ]] || { echo "expected 2, got $EC" >&2; exit 1; }
grep -qi "unknown subcommand" "$EVIDENCE_DIR/unknown-subcommand.stderr.txt" || \
    { echo "stderr lacks 'unknown subcommand'" >&2; exit 1; }
echo "OK — unknown subcommand exits 2 with diagnostic"
