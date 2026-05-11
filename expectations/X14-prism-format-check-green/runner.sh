#!/usr/bin/env bash
# X14 — prism-format-check-green. Build-engineer Prism gate.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

SNAPSHOT_DIR="$HARNESS_DIR/.snapshot"
CACHE_DIR="$HARNESS_DIR/.workspace-build-cache"
mkdir -p "$CACHE_DIR/pnpm-store"

docker run --rm \
    -v "$SNAPSHOT_DIR:/src:rw" \
    -v "$CACHE_DIR/pnpm-store:/pnpm-store:rw" \
    -e PNPM_HOME=/pnpm \
    -e PATH=/pnpm:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    -w /src \
    node:22-slim \
    bash -c '
        set -euo pipefail
        corepack enable
        corepack prepare pnpm@9.15.0 --activate >/dev/null
        pnpm config set store-dir /pnpm-store
        pnpm install --frozen-lockfile
        echo "--- pnpm -F prism format:check ---"
        pnpm -F prism format:check
        echo "FORMAT_OK"
    ' > "$EVIDENCE_DIR/X14.stdout.txt" 2> "$EVIDENCE_DIR/X14.stderr.txt"

echo "  tail:"; tail -8 "$EVIDENCE_DIR/X14.stdout.txt" | sed 's/^/    /'
grep -q "^FORMAT_OK$" "$EVIDENCE_DIR/X14.stdout.txt" || { echo "no FORMAT_OK marker" >&2; exit 1; }
echo "OK — prettier --check is green"
