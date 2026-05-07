#!/usr/bin/env bash
# run-expectation.sh — verify one kaleidoscope expectation end-to-end.
#
# Records the kaleidoscope SHA + dirty state, brings the dockerised
# harness up, optionally runs a per-expectation runner, captures
# evidence, tears the harness down. Exits with the runner's exit code
# (or 0 if no runner is present and the harness reached steady state).
#
# Usage:
#   ./run-expectation.sh <ID>
# Where <ID> is e.g. A01, S03, E02, X07.
#
# Env vars:
#   KALEIDOSCOPE_DIR  source path to build aperture from (default ~/dev/kaleidoscope)
#   APERTURE_LOG      RUST_LOG passed to aperture (default info)

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "usage: $0 <ID>  (e.g. A01)" >&2
    exit 64
fi

EXPECTATION_ID="$1"
KALEIDOSCOPE_DIR="${KALEIDOSCOPE_DIR:-$HOME/dev/kaleidoscope}"

HARNESS_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HARNESS_DIR/.." && pwd)"

# Resolve the expectation directory by ID prefix.
EXP_DIR="$(find "$REPO_ROOT/expectations" -maxdepth 1 -mindepth 1 -type d -name "${EXPECTATION_ID}-*" | head -n 1)"
if [[ -z "$EXP_DIR" ]]; then
    echo "no expectation directory matches '${EXPECTATION_ID}' under $REPO_ROOT/expectations" >&2
    exit 64
fi
EVIDENCE_DIR="$EXP_DIR/evidence"
mkdir -p "$EVIDENCE_DIR"

# Sanity-check kaleidoscope source path.
if [[ ! -d "$KALEIDOSCOPE_DIR/.git" ]]; then
    echo "KALEIDOSCOPE_DIR='$KALEIDOSCOPE_DIR' is not a git working tree" >&2
    exit 65
fi

# 1. Pin kaleidoscope state.
KALEIDOSCOPE_SHA="$(git -C "$KALEIDOSCOPE_DIR" rev-parse HEAD)"
KALEIDOSCOPE_PORCELAIN="$(git -C "$KALEIDOSCOPE_DIR" status --porcelain)"
if [[ -n "$KALEIDOSCOPE_PORCELAIN" ]]; then
    KALEIDOSCOPE_DIRTY="yes"
    git -C "$KALEIDOSCOPE_DIR" diff > "$EVIDENCE_DIR/kaleidoscope-dirty.diff"
    git -C "$KALEIDOSCOPE_DIR" status --porcelain > "$EVIDENCE_DIR/kaleidoscope-dirty.status"
else
    KALEIDOSCOPE_DIRTY="no"
    rm -f "$EVIDENCE_DIR/kaleidoscope-dirty.diff" "$EVIDENCE_DIR/kaleidoscope-dirty.status"
fi

VERIFIED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
HOST_UNAME="$(uname -a)"

cat > "$EVIDENCE_DIR/verification.yaml" <<EOF
expectation_id: "${EXPECTATION_ID}"
verified_at_utc: "${VERIFIED_AT}"
kaleidoscope_dir: "${KALEIDOSCOPE_DIR}"
kaleidoscope_sha: "${KALEIDOSCOPE_SHA}"
kaleidoscope_dirty: "${KALEIDOSCOPE_DIRTY}"
host_uname: "${HOST_UNAME}"
harness_dir: "${HARNESS_DIR}"
EOF

# 2. Snapshot kaleidoscope HEAD into a staging dir.
#
# We deliberately DO NOT build from the live working tree:
# - the working tree may be dirty (the methodology saves the diff as
#   evidence but does not feed it to the build);
# - the working tree is a moving target while the parallel
#   kaleidoscope-developing session is active, so its content can
#   change mid-context-load (~90 s on a fresh build);
# - `git archive` excludes `target/`, `mutants.out/`, `.git/`, and
#   any other gitignored noise, keeping the docker build context
#   small and pristine.
SNAPSHOT_DIR="$HARNESS_DIR/.snapshot"
rm -rf "$SNAPSHOT_DIR"
mkdir -p "$SNAPSHOT_DIR"
git -C "$KALEIDOSCOPE_DIR" archive HEAD | tar -x -C "$SNAPSHOT_DIR"

# 3. Bring the harness up. Compose's `additional_contexts` reads
#    KALEIDOSCOPE_DIR; we redirect it to the snapshot so the build
#    is reproducible from the recorded SHA, not from whatever the
#    working tree happens to be at this exact moment.
cd "$HARNESS_DIR"
mkdir -p .captured
# Truncate the otelcol-sink capture file from any previous run so the
# scenario starts with an empty observed-OTLP stream.
: > .captured/otlp-received.jsonl

export KALEIDOSCOPE_DIR="$SNAPSHOT_DIR"

# Optional per-expectation env-var overrides for aperture (passed
# through to the container per docker-compose.yml's environment:
# block). The file is bash-sourced; declare with `export`.
if [[ -f "$EXP_DIR/.env-overrides" ]]; then
    echo "sourcing per-expectation env overrides from $EXP_DIR/.env-overrides" >&2
    cp "$EXP_DIR/.env-overrides" "$EVIDENCE_DIR/.env-overrides.copy"
    # shellcheck disable=SC1091
    set -a; . "$EXP_DIR/.env-overrides"; set +a
fi

# Optional per-expectation aperture.toml: when an expectation ships
# its own aperture.toml, point compose at it via APERTURE_TOML
# (consumed by docker-compose.yml's volume substitution). Useful for
# expectations that need a tighter cap, a different sink, etc.,
# while issue 002 (env-var loader not wired) blocks the env-var path.
if [[ -f "$EXP_DIR/aperture.toml" ]]; then
    export APERTURE_TOML="$EXP_DIR/aperture.toml"
    echo "using per-expectation aperture.toml: $APERTURE_TOML" >&2
    cp "$APERTURE_TOML" "$EVIDENCE_DIR/aperture.toml.used"
fi

# Per-expectation opt-out for the compose stack. X-prefix
# expectations (static reads, cargo workflows) don't need a running
# aperture instance and pay no benefit for one. Bringing the stack
# up under heavy parallel load (e.g. an in-progress `cargo test
# --workspace`) can starve the Docker Desktop VM and cause aperture
# to miss the readiness gate. Drop a `.no-compose` marker file in
# the expectation directory to skip compose entirely.
SKIP_COMPOSE=0
if [[ -f "$EXP_DIR/.no-compose" ]]; then
    SKIP_COMPOSE=1
    echo "skipping compose stack for ${EXPECTATION_ID} (.no-compose marker present)" >&2
fi

if (( SKIP_COMPOSE == 0 )); then
    docker compose up -d --build
fi

if (( SKIP_COMPOSE == 0 )); then
    # Centralised readiness wait. Cold runs (fresh snapshot,
    # invalidated aperture build cache after a kaleidoscope commit
    # touches aperture sources) can take >60 s before /readyz
    # returns 200, so we give 180 s of slack. Subsequent runs hit
    # the cargo cache and complete in seconds.
    echo "waiting for aperture /readyz=200 (centralised, ≤ 180 s)" >&2
    READINESS_DEADLINE=$(( SECONDS + 180 ))
    READY=0
    while (( SECONDS < READINESS_DEADLINE )); do
        if curl -sS --max-time 2 -o /dev/null -w '%{http_code}' \
                http://localhost:4318/readyz 2>/dev/null \
                | grep -q '^200$'; then
            READY=1
            echo "  aperture ready" >&2
            break
        fi
        sleep 1
    done
    if (( READY == 0 )); then
        echo "aperture never reached /readyz=200 within the centralised window" >&2
        docker compose logs --no-color aperture > "$EVIDENCE_DIR/aperture.stderr.txt" 2>&1 || true
        docker compose down --volumes --remove-orphans >/dev/null 2>&1 || true
        exit 70
    fi
fi

# 3. Run the per-expectation scenario, if present.
RUNNER="$EXP_DIR/runner.sh"
RUNNER_EXIT=0
# Compose network name. With `name: kaleidoscope-expectations` in
# docker-compose.yml the default network is named `<project>_default`.
COMPOSE_NETWORK="kaleidoscope-expectations_default"
CAPTURED_FILE="$HARNESS_DIR/.captured/otlp-received.jsonl"

if [[ -x "$RUNNER" ]]; then
    echo "running scenario: $RUNNER" >&2
    if ( cd "$EXP_DIR" \
            && HARNESS_DIR="$HARNESS_DIR" \
               COMPOSE_NETWORK="$COMPOSE_NETWORK" \
               CAPTURED_FILE="$CAPTURED_FILE" \
               ./runner.sh "$EVIDENCE_DIR" ) \
            > "$EVIDENCE_DIR/runner.stdout.txt" \
            2> "$EVIDENCE_DIR/runner.stderr.txt"; then
        RUNNER_EXIT=0
    else
        RUNNER_EXIT=$?
    fi
else
    echo "no executable runner.sh in $EXP_DIR — capturing baseline only" >&2
fi

# 4. Capture aperture stderr and downstream sink contents (only if
#    compose was actually brought up).
if (( SKIP_COMPOSE == 0 )); then
    docker compose logs --no-color aperture > "$EVIDENCE_DIR/aperture.stderr.txt" 2>&1 || true
    docker compose logs --no-color otelcol-sink > "$EVIDENCE_DIR/otelcol-sink.stderr.txt" 2>&1 || true
    if [[ -f .captured/otlp-received.jsonl ]]; then
        cp -a .captured/otlp-received.jsonl "$EVIDENCE_DIR/otlp-received.jsonl"
    fi

    {
        echo "# images_used.txt — generated by run-expectation.sh"
        docker compose images || true
    } > "$EVIDENCE_DIR/images-used.txt"

    # 5. Tear down.
    docker compose down --volumes --remove-orphans >/dev/null 2>&1 || true
fi

if [[ "$RUNNER_EXIT" -ne 0 ]]; then
    echo "scenario runner exited ${RUNNER_EXIT}" >&2
    exit "$RUNNER_EXIT"
fi

echo "evidence captured under $EVIDENCE_DIR" >&2
