#!/usr/bin/env bash
# X15 — prism-bundle-size-within-budget. Build-engineer Prism gate.
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
        apt-get update >/dev/null
        apt-get install -y --no-install-recommends git >/dev/null
        rm -rf /var/lib/apt/lists/*
        corepack enable
        corepack prepare pnpm@9.15.0 --activate >/dev/null
        pnpm config set store-dir /pnpm-store
        pnpm install --frozen-lockfile
        # The bundle-size script calls `git rev-parse HEAD` to tag
        # the report; our snapshot has no .git/ (git archive output),
        # so seed a minimal repo to satisfy the read.
        git config --global user.email "edd@invalid" >/dev/null
        git config --global user.name "edd-fixture" >/dev/null
        git init -q
        git add -A 2>/dev/null
        git commit -q -m "snapshot" --allow-empty
        echo "--- pnpm -F prism build (bundle-size needs dist/) ---"
        pnpm -F prism build
        echo "--- pnpm -F prism bundle-size ---"
        pnpm -F prism bundle-size
        echo "BUNDLE_OK"
    ' > "$EVIDENCE_DIR/X15.stdout.txt" 2> "$EVIDENCE_DIR/X15.stderr.txt"

echo "  tail:"; tail -8 "$EVIDENCE_DIR/X15.stdout.txt" | sed 's/^/    /'
grep -q "^BUNDLE_OK$" "$EVIDENCE_DIR/X15.stdout.txt" || { echo "no BUNDLE_OK marker" >&2; exit 1; }
echo "OK — bundle-size script is green (within budget)"
