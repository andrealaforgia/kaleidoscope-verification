#!/usr/bin/env bash
# K11 — kaleidoscope-cli rejects an unknown flag as a usage error:
# exit 2 with the usage block on stderr, BEFORE any I/O. Re-anchored
# at 307e447 ("feat(kaleidoscope-cli): reject unknown subcommand
# flags, re-anchoring K11") after the original anchor e7fbee0 was
# reverted en bloc (N14). The real fix this commit carries: a known
# SUBCOMMAND with an unknown flag (e.g. `read ... --bogus`) used to
# exit 0 and silently ignore the flag; a shared reject_unknown_flags
# helper now runs per subcommand during parse and turns it into the
# same exit-2 usage error the top level already gave.
#
# Cases (per the implementer's stated contract):
#   (a) `--bogus`                         -> exit 2 + usage  (top-level)
#   (b) `bogus-subcommand`                -> exit 2 + usage
#   (c) `read acme /data --bogus`         -> exit 2 + usage  (THE FIX)
#   (d) `read acme /data --since <ts>`    -> a KNOWN flag is NOT a usage
#       error (no exit-2 usage block; the flag is accepted into parsing)
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
run_case() {
    local label="$1"; shift
    local ec=0
    docker run --rm -v "$DATA_HOST:/data" "$KCLI_IMAGE" "$@" \
        > "/tmp/${label}.out" 2> "/tmp/${label}.err" || ec=$?
    echo "${label}_exit=$ec"
    cp "/tmp/${label}.err" "'"$EVIDENCE_DIR"'/${label}.stderr.txt"
}
run_case a_toplevel   --bogus
run_case b_badsub     bogus-subcommand
run_case c_read_bogus read acme /data --bogus
run_case d_read_known read acme /data --since 2020-01-01T00:00:00Z
'
"$HARNESS_DIR/run-kaleidoscope-cli.sh" "$EVIDENCE_DIR" K11 "$INLINE"

OUT="$EVIDENCE_DIR/K11.stdout.txt"
ec() { grep -oE "${1}_exit=[0-9]+" "$OUT" | tail -1 | cut -d= -f2; }
USAGE_MARKER='kaleidoscope-cli — operator CLI'

# (a)(b)(c): each rejection is exit 2 with the usage block on stderr.
for c in a_toplevel b_badsub c_read_bogus; do
    [[ "$(ec $c)" == "2" ]] || { echo "$c expected exit 2, got $(ec $c)" >&2; exit 1; }
    grep -qF "$USAGE_MARKER" "$EVIDENCE_DIR/$c.stderr.txt" \
        || { echo "$c exit 2 but no usage block on stderr" >&2; cat "$EVIDENCE_DIR/$c.stderr.txt" >&2; exit 1; }
done

# (d): a KNOWN flag is NOT rejected — no exit-2 usage error. (read may
# still exit non-zero on an empty store, but it must NOT be the exit-2
# usage-block rejection.)
[[ "$(ec d_read_known)" != "2" ]] || { echo "d_read_known: a known flag (--since) was wrongly treated as exit-2 usage error" >&2; cat "$EVIDENCE_DIR/d_read_known.stderr.txt" >&2; exit 1; }
if grep -qF "$USAGE_MARKER" "$EVIDENCE_DIR/d_read_known.stderr.txt"; then
    echo "d_read_known: known flag --since produced the usage block (wrongly rejected)" >&2; exit 1
fi

echo "OK — kaleidoscope-cli rejects unknown flags as exit-2 usage errors: top-level --bogus, bogus-subcommand, AND the re-anchored fix 'read ... --bogus' (was exit 0); a known flag (--since) is parsed, not rejected"
