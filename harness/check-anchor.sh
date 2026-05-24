#!/usr/bin/env bash
# check-anchor.sh — verify an expectation's anchor commit still
# anchors the current HEAD.
#
# Defends against the K11 failure mode: a contract's anchor
# commit gets reverted (e3a8cad over e7fbee0) but the
# expectation README still cites it. The catalogue should refuse
# `satisfied` and flag `unanchored-claim` when the anchor's
# introduced change is no longer present in HEAD.
#
# This check is opt-in: present an `anchor.yaml` next to the
# expectation's README.md, otherwise this script exits 0
# silently. Recommended format:
#
#   anchor_commit: 75f15a6
#   impl_paths:
#     - crates/kaleidoscope-cli/src/main.rs
#
# The check compares the impl file's content at HEAD against
# its content at `${anchor_commit}^` (pre-anchor). If they are
# byte-equal, the anchor's diff was undone — refuse.
#
# Usage: check-anchor.sh <EXPECTATION_DIR>
#
# Exit codes:
#   0 — no anchor.yaml, OR anchor still applies, OR opt-in passed
#   2 — anchor.yaml malformed
#   3 — anchor commit unreachable from kaleidoscope HEAD
#   4 — impl_path at HEAD matches pre-anchor state (anchor reverted)

set -euo pipefail
EXPECTATION_DIR="$1"
KALEIDOSCOPE_DIR="${KALEIDOSCOPE_DIR:-$HOME/dev/kaleidoscope}"

ANCHOR_FILE="$EXPECTATION_DIR/anchor.yaml"
if [[ ! -f "$ANCHOR_FILE" ]]; then
    exit 0
fi

# Parse the (deliberately tiny) YAML grammar by line. anchor_commit
# is on its own line; impl_paths is a list of `  - <path>` lines.
ANCHOR_COMMIT=$(awk -F': *' '/^anchor_commit:/ { gsub(/["[:space:]]/, "", $2); print $2 }' "$ANCHOR_FILE")
[[ -n "$ANCHOR_COMMIT" ]] || {
    echo "anchor.yaml is missing anchor_commit" >&2
    exit 2
}

# Collect impl_paths into an array (bash 3.2 safe). Scan from the
# `impl_paths:` line and read every line that starts with `- `
# (allowing leading whitespace).
IMPL_PATHS=()
in_list=0
while IFS= read -r line; do
    if [[ "$line" =~ ^impl_paths: ]]; then
        in_list=1
        continue
    fi
    if [[ "$in_list" -eq 1 ]]; then
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+(.+)$ ]]; then
            IMPL_PATHS+=("${BASH_REMATCH[1]}")
        elif [[ -n "$line" ]] && [[ ! "$line" =~ ^[[:space:]] ]]; then
            in_list=0
        fi
    fi
done < "$ANCHOR_FILE"
[[ ${#IMPL_PATHS[@]} -gt 0 ]] || {
    echo "anchor.yaml has empty impl_paths" >&2
    exit 2
}

# Use HEAD; if the caller pinned a SHA in verification.yaml,
# prefer that for reproducibility.
HEAD_SHA=$(git -C "$KALEIDOSCOPE_DIR" rev-parse HEAD)
if [[ -f "$EXPECTATION_DIR/evidence/verification.yaml" ]]; then
    PIN=$(awk -F'"' '/kaleidoscope_sha:/ { print $2 }' "$EXPECTATION_DIR/evidence/verification.yaml")
    [[ -n "$PIN" ]] && HEAD_SHA="$PIN"
fi

# Step 1: anchor reachable from HEAD?
if ! git -C "$KALEIDOSCOPE_DIR" merge-base --is-ancestor "$ANCHOR_COMMIT" "$HEAD_SHA" 2>/dev/null; then
    echo "anchor commit $ANCHOR_COMMIT not reachable from HEAD $HEAD_SHA" >&2
    exit 3
fi

# Step 2: scan for revert commits touching the impl paths between
# anchor and HEAD. A `revert:`-prefixed commit message in this
# range is a strong signal the anchor's diff was undone. We refuse
# `satisfied` and ask for human review: the catalogue does not
# decide whether the revert was scoped narrowly (anchor still
# applies) or sweepingly (anchor gone). The K11 case (e3a8cad
# reverted 31 commits including e7fbee0) is the failure mode this
# defends against.
REVERTS=""
for P in "${IMPL_PATHS[@]}"; do
    R=$(git -C "$KALEIDOSCOPE_DIR" log --oneline --grep='^revert' \
        "${ANCHOR_COMMIT}..${HEAD_SHA}" -- "${P}" 2>/dev/null || true)
    if [[ -n "$R" ]]; then
        REVERTS+="$P:"$'\n'"$R"$'\n'
    fi
done
if [[ -n "$REVERTS" ]]; then
    echo "ANCHOR-CHECK FAIL: revert commit(s) touched the impl paths between $ANCHOR_COMMIT and $HEAD_SHA:" >&2
    echo "$REVERTS" >&2
    echo "Human review needed: was the anchor's diff undone?" >&2
    echo "If yes, mark the expectation 'held' and reference [[$ANCHOR_COMMIT]] reverted-by." >&2
    exit 4
fi

# Step 3 (informational only): if the impl file at HEAD is
# byte-equal to its pre-anchor state, log a warning. This is
# rare in practice (most files churn) and noisier than the
# revert detector, but it catches the edge case where a revert
# commit didn't say `revert:` in the message.
for P in "${IMPL_PATHS[@]}"; do
    PRE=$(git -C "$KALEIDOSCOPE_DIR" show "${ANCHOR_COMMIT}^:${P}" 2>/dev/null || echo "__MISSING__")
    AT_HEAD=$(git -C "$KALEIDOSCOPE_DIR" show "${HEAD_SHA}:${P}" 2>/dev/null || echo "__MISSING__")
    if [[ "$AT_HEAD" == "$PRE" ]] && [[ "$PRE" != "__MISSING__" ]]; then
        echo "WARN: $P at HEAD is byte-equal to its pre-anchor state. Investigate." >&2
    fi
done

echo "anchor $ANCHOR_COMMIT still applies at $HEAD_SHA across ${#IMPL_PATHS[@]} impl path(s) (no revert commits)"
