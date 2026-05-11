#!/usr/bin/env bash
# X11 — prism-typecheck-green. Build-engineer Prism gate; runs inside
# node:22-slim against the kaleidoscope HEAD snapshot.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

SNAPSHOT_DIR="$HARNESS_DIR/.snapshot"
CACHE_DIR="$HARNESS_DIR/.workspace-build-cache"
mkdir -p "$CACHE_DIR/pnpm-store"

echo "step 1: pnpm install + pnpm -F prism typecheck"
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
        echo "--- pnpm -F prism typecheck ---"
        pnpm -F prism typecheck
        echo "TYPECHECK_OK"
    ' \
    > "$EVIDENCE_DIR/X11.stdout.txt" \
    2> "$EVIDENCE_DIR/X11.stderr.txt"

echo "  tail:"
tail -10 "$EVIDENCE_DIR/X11.stdout.txt" | sed 's/^/    /'

if ! grep -q "^TYPECHECK_OK$" "$EVIDENCE_DIR/X11.stdout.txt"; then
    echo "did not reach TYPECHECK_OK marker" >&2
    exit 1
fi

echo "OK — pnpm -F prism typecheck (tsc -b --noEmit) is green"
