#!/usr/bin/env bash
# CR05 — the consolidated runtime FAILS CLOSED on a listener bind conflict
# (implementer msg 037; ADR-0076 DD3 wire->probe->use). If one of the five
# listeners cannot bind, the process refuses to start (event=health.startup.refused,
# non-zero exit) and leaves NO half-up serving on the other listeners.
#
# Robust conflict: boot runtime #1 (binds 4317/4318/9090/9091/9092), then boot
# runtime #2 in #1's network namespace (--network container:<rt1>) with its OWN
# ephemeral pillar root. #2 builds + probes its own empty stores fine, then hits
# the query-listener bind step (the startup order binds the three query
# TcpListeners for cheap port-conflict detection) and collides on 9090/9091/9092
# already held by #1. It must refuse, not serve a partial set.
#
# Asserts: #2 exits NON-ZERO within a bounded window (no half-up hang) with a
# refusal reason on its log; and #1 (the incumbent) keeps serving, undisturbed.
#
# Transition-proof: RED if #2 stays up (still running = half-up fail-open) or
# exits 0 despite the conflict, or refuses silently (no reason on the log).
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
RT1="cr05-rt1-$$"; RT2="cr05-rt2-$$"
cleanup() { docker stop --time 5 "$RT1" "$RT2" >/dev/null 2>&1 || true; docker rm "$RT1" "$RT2" >/dev/null 2>&1 || true; }
trap cleanup EXIT

RNOW=$(date -u +%s)
qurl="http://localhost:19130/api/v1/query_range?query=gen&start=$((RNOW-300))&end=${RNOW}&step=15s"

# 1. incumbent runtime #1, binds all five listeners. Real 200 readiness (NOT a
#    bare 3-digit match -- 000 is connection-refused, must not count as ready).
docker run -d --name "$RT1" -v "$DATA_HOST:/data" -e KALEIDOSCOPE_TENANT=acme -e RUST_LOG=info -p 19130:9090 "$CRT_IMAGE" > /dev/null
R1=""
for _ in $(seq 1 40); do
    [[ "$(curl -sS -o /dev/null -w "%{http_code}" "$qurl" 2>/dev/null)" == "200" ]] && { R1=yes; break; }
    sleep 1
done
[[ "$R1" == "yes" ]] || { echo "incumbent runtime #1 never became ready" >&2; docker logs "$RT1" >&2 || true; exit 1; }

# 2. runtime #2 shares #1 netns, own ephemeral /data -> query-listener bind must
#    collide. Detached + docker-inspect polling (no `timeout`, absent on macOS).
docker run -d --name "$RT2" --network "container:$RT1" -e KALEIDOSCOPE_TENANT=acme -e RUST_LOG=info "$CRT_IMAGE" > /dev/null 2>&1 || true
RT_EXIT=running
for _ in $(seq 1 40); do
    st=$(docker inspect -f "{{.State.Status}}" "$RT2" 2>/dev/null || echo gone)
    [[ "$st" == "exited" ]] && { RT_EXIT=$(docker inspect -f "{{.State.ExitCode}}" "$RT2" 2>/dev/null); break; }
    [[ "$st" == "gone" ]] && { RT_EXIT=gone; break; }
    sleep 1
done
echo "rt_exit=${RT_EXIT}"
docker logs "$RT2" > /tmp/rt2.err 2>&1 || true
cp /tmp/rt2.err "'"$EVIDENCE_DIR"'/runtime2.stderr.txt" 2>/dev/null || true

# 3. the incumbent must be undisturbed by #2 refusing.
echo "rt1_still=$(curl -sS -o /dev/null -w "%{http_code}" "$qurl" 2>/dev/null || echo 000)"
echo "refused_event=$(grep -c "health.startup.refused" /tmp/rt2.err 2>/dev/null || echo 0)"
echo "bind_reason=$(grep -ciE "address.*in use|addrinuse|already in use|bind" /tmp/rt2.err 2>/dev/null || echo 0)"
'
"$HARNESS_DIR/run-kaleidoscope-runtime.sh" "$EVIDENCE_DIR" CR05 "$INLINE"

OUT="$EVIDENCE_DIR/CR05.stdout.txt"
f() { grep -oE "$1=[^ ]+" "$OUT" | tail -1 | cut -d= -f2; }
fail() { echo "FAIL: $1" >&2; cat "$OUT" >&2; echo "--- rt2 stderr ---" >&2; cat "$EVIDENCE_DIR/runtime2.stderr.txt" 2>/dev/null | tail -15 >&2; exit 1; }

RTE=$(f rt_exit)
[[ "$RTE" == "running" ]] && fail "runtime #2 did NOT refuse on the port conflict — still running after the window (half-up, fail-open: a listener failed to bind yet the process kept serving; ADR-0076 DD3 violated)"
[[ "$RTE" == "gone" ]] && fail "runtime #2 vanished (could not read exit code) — inconclusive harness state"
[[ "$RTE" =~ ^[0-9]+$ ]] || fail "could not read runtime #2 exit code ($RTE)"
[[ "$RTE" != "0" ]] || fail "runtime #2 exited 0 despite the port conflict — did not fail closed"
REF=$(f refused_event); BR=$(f bind_reason)
[[ "$REF" -ge 1 || "$BR" -ge 1 ]] 2>/dev/null || fail "runtime #2 exited non-zero ($RTE) but its log names no health.startup.refused and no bind/address-in-use reason — silent refusal (operator cannot tell why)"
[[ "$(f rt1_still)" == "200" ]] || fail "the incumbent runtime #1 stopped serving (got $(f rt1_still)) after #2 refused — #2's failure disturbed the running process"

echo "CR05 satisfied — consolidated runtime fails closed on a listener bind conflict: the second process exits ${RTE} (non-zero, not a hang) with a refusal reason on its log (health.startup.refused=${REF}, bind/in-use markers=${BR}), no half-up serving, and the incumbent stays up (200). ADR-0076 DD3 wire->probe->use holds."
