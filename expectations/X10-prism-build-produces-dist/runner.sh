#!/usr/bin/env bash
# X10 — `pnpm install && pnpm -F prism build` against the
# kaleidoscope HEAD snapshot produces a `apps/prism/dist/` artefact
# containing a built SPA (index.html + assets). Build-engineer
# contract for the Prism v0 frontend.

set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

SNAPSHOT_DIR="$HARNESS_DIR/.snapshot"
CACHE_DIR="$HARNESS_DIR/.workspace-build-cache"
mkdir -p "$CACHE_DIR/pnpm-store" "$CACHE_DIR/prism-node-modules"

echo "step 1: pnpm install + pnpm -F prism build inside node:22-slim"
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
        corepack prepare pnpm@9.15.0 --activate
        pnpm config set store-dir /pnpm-store
        echo "--- pnpm version ---"
        pnpm --version
        echo "--- pnpm install (frozen lockfile) ---"
        pnpm install --frozen-lockfile
        echo "--- pnpm -F prism build ---"
        pnpm -F prism build
        echo "--- prism dist listing ---"
        ls -la apps/prism/dist/
        echo "--- index.html head ---"
        head -3 apps/prism/dist/index.html
        echo "DONE"
    ' \
    > "$EVIDENCE_DIR/build.stdout.txt" \
    2> "$EVIDENCE_DIR/build.stderr.txt"

echo "  build done; tail:"
tail -10 "$EVIDENCE_DIR/build.stdout.txt" | sed 's/^/    /'

# Capture the dist listing as separate evidence.
grep -E "^-rw-|^drwx" "$EVIDENCE_DIR/build.stdout.txt" > "$EVIDENCE_DIR/dist-listing.txt" || true

# Sanity assertions.
if ! grep -q "^DONE$" "$EVIDENCE_DIR/build.stdout.txt"; then
    echo "build did not reach DONE marker" >&2
    exit 1
fi
if ! grep -q "index.html" "$EVIDENCE_DIR/dist-listing.txt"; then
    echo "no index.html in prism dist" >&2
    exit 1
fi
if ! grep -q "assets" "$EVIDENCE_DIR/dist-listing.txt"; then
    echo "no assets directory in prism dist" >&2
    exit 1
fi

echo "OK — pnpm -F prism build produced a dist/ artefact with index.html + assets"
