#!/usr/bin/env bash
# re-verify-all.sh — re-run every currently-satisfied expectation
# against the current kaleidoscope HEAD. Used when the upstream
# session has progressed and we want to know which expectations
# stayed green and which regressed.
#
# Reads the satisfied IDs by scanning each expectation's README.md
# for "Status: `satisfied`". Skips deferred / pending /
# out-of-scope.
#
# Per-expectation outcome is recorded in
# .re-verify-summary/<ID>.{ok|broken}.txt with the runner's exit
# code. The final summary is printed at the end.

set -uo pipefail
HARNESS_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HARNESS_DIR/.." && pwd)"

SUMMARY_DIR="$HARNESS_DIR/.re-verify-summary"
rm -rf "$SUMMARY_DIR"
mkdir -p "$SUMMARY_DIR"

SHA="$(git -C "${KALEIDOSCOPE_DIR:-$HOME/dev/kaleidoscope}" rev-parse HEAD)"
echo "re-verifying against kaleidoscope HEAD = ${SHA}"
echo ""

# Enumerate satisfied expectations. (bash 3.2 compatible — no
# `mapfile` builtin on macOS's stock bash.)
SATISFIED=()
while IFS= read -r id; do
    SATISFIED+=("$id")
done < <(
    for dir in "$REPO_ROOT"/expectations/*/; do
        readme="$dir/README.md"
        [[ -f "$readme" ]] || continue
        if grep -q '^- Status: `satisfied`$' "$readme"; then
            basename "$dir" | cut -d- -f1
        fi
    done | sort
)

echo "found ${#SATISFIED[@]} satisfied expectations to re-verify:"
printf '  %s\n' "${SATISFIED[@]}"
echo ""

GREEN_IDS=()
BROKEN_IDS=()

for id in "${SATISFIED[@]}"; do
    echo "=========================================="
    echo "re-verifying ${id}"
    echo "=========================================="
    LOG="$SUMMARY_DIR/${id}.log"
    if "$HARNESS_DIR/run-expectation.sh" "$id" > "$LOG" 2>&1; then
        echo "  ${id}: GREEN"
        echo "exit=0 sha=${SHA}" > "$SUMMARY_DIR/${id}.ok.txt"
        GREEN_IDS+=("$id")
    else
        rc=$?
        echo "  ${id}: BROKEN (runner exit ${rc})"
        echo "exit=${rc} sha=${SHA}" > "$SUMMARY_DIR/${id}.broken.txt"
        BROKEN_IDS+=("$id")
    fi
    echo ""
done

echo "=========================================="
echo "summary @ ${SHA}"
echo "=========================================="
echo "green:  ${#GREEN_IDS[@]} (${GREEN_IDS[*]:-none})"
echo "broken: ${#BROKEN_IDS[@]} (${BROKEN_IDS[*]:-none})"
echo ""
echo "per-expectation logs under: ${SUMMARY_DIR}"

if (( ${#BROKEN_IDS[@]} > 0 )); then
    exit 1
fi
exit 0
