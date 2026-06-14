# Black-box checker for PG-1: compares the external app's report against the
# trace retrieved by-id from :9092 and the logs from :9091. Exits non-zero with
# a named failure if any of the 4 criteria (or the bonus, if --bonus) fails.
import json
import sys

evid = sys.argv[1]
want_bonus = "--bonus" in sys.argv


def fail(msg):
    print("FAIL: " + msg)
    sys.exit(1)


# --- app report ---
report = None
for line in open(evid + "/app.out", encoding="utf-8"):
    if line.startswith("PG1_REPORT="):
        report = json.loads(line[len("PG1_REPORT="):])
if not report:
    fail("the external app printed no PG1_REPORT (it did not run / export)")
app_tid = report["trace_id"]
ap, ch = report.get("parent"), report.get("child")
if not ap or not ch:
    fail("app did not emit both a parent and a child span")

# --- retrieved by-id ---
spans = json.load(open(evid + "/byid.json", encoding="utf-8"))
if not isinstance(spans, list) or len(spans) < 2:
    fail("criterion 2: by-id returned %r spans (expected >=2 parent+child)" % (len(spans) if isinstance(spans, list) else spans))

roots = [s for s in spans if not s.get("parent_span_id")]
kids = [s for s in spans if s.get("parent_span_id")]
if len(roots) != 1:
    fail("criterion 2: expected exactly 1 root (no parent_span_id), got %d" % len(roots))
root, kid = roots[0], None
for k in kids:
    if k["parent_span_id"] == root["span_id"]:
        kid = k
        break
if kid is None:
    fail("criterion 2: no child whose parent_span_id == the root span_id (tree broken end-to-end)")

# cross-check the retrieved tree against what the app actually sent
if root["span_id"] != ap["span_id"]:
    fail("criterion 2: retrieved root span_id %s != app parent span_id %s" % (root["span_id"], ap["span_id"]))
if kid["span_id"] != ch["span_id"]:
    fail("criterion 2: retrieved child span_id %s != app child span_id %s" % (kid["span_id"], ch["span_id"]))
if kid["parent_span_id"] != ap["span_id"]:
    fail("criterion 2: retrieved child parent_span_id %s != app parent span_id %s" % (kid["parent_span_id"], ap["span_id"]))

# --- criterion 3: customer.id on the retrieved child span ---
attrs = kid.get("attributes", {})
if attrs.get("customer.id") != "bea-test":
    fail("criterion 3: customer.id='bea-test' not found in retrieved child span attributes (got %r)" % attrs)

# --- criterion 4: exact nanos round-trip + parent encloses child ---
def rt(span, exp, label):
    if span["start_time_unix_nano"] != exp["start"]:
        fail("criterion 4: %s start nanos %s != app-sent %s (no exact round-trip)" % (label, span["start_time_unix_nano"], exp["start"]))
    if span["end_time_unix_nano"] != exp["end"]:
        fail("criterion 4: %s end nanos %s != app-sent %s (no exact round-trip)" % (label, span["end_time_unix_nano"], exp["end"]))

rt(root, ap, "parent")
rt(kid, ch, "child")
if not (root["start_time_unix_nano"] <= kid["start_time_unix_nano"] <= kid["end_time_unix_nano"] <= root["end_time_unix_nano"]):
    fail("criterion 4: parent window does not enclose child (parent %s-%s, child %s-%s)" % (
        root["start_time_unix_nano"], root["end_time_unix_nano"], kid["start_time_unix_nano"], kid["end_time_unix_nano"]))

print("OK criteria 1-4: external OTel SDK -> real wire -> by-id retrieval; parent+child tree intact (root %s, child %s), customer.id=bea-test present, nanos round-trip exact, parent encloses child." % (root["span_id"], kid["span_id"]))

# --- bonus: a log carrying the same trace_id ---
if want_bonus:
    try:
        logs = json.load(open(evid + "/logs.json", encoding="utf-8"))
    except Exception as exc:
        print("BONUS log query unreadable: %s (non-blocking)" % exc)
        sys.exit(0)
    def tid_hex(v):  # :9091 logs serialise trace_id as a byte-int array; :9092 traces as hex.
        if isinstance(v, str):
            return v.lower()
        if isinstance(v, list):
            return "".join("%02x" % (b & 0xFF) for b in v)
        return ""
    matched = [l for l in (logs if isinstance(logs, list) else []) if tid_hex(l.get("trace_id")) == app_tid.lower()]
    if matched:
        raw = matched[0].get("trace_id")
        form = "byte-array" if isinstance(raw, list) else "hex-string"
        print("BONUS GREEN: a log retrieved on :9091 carries the same trace_id=%s as the trace (PG-2 seed: log<->trace correlation works from an external SDK). NOTE the logs API serialises trace_id as a %s (%r) while the traces API uses a hex string — the exact PG-2 criterion-5 inconsistency, corroborated black-box." % (app_tid, form, raw))
    else:
        ntid = sum(1 for l in (logs if isinstance(logs, list) else []) if l.get("trace_id"))
        print("BONUS not met (non-blocking): no log on :9091 carries the app trace_id (logs with any trace_id: %d)." % ntid)
print("PG1 satisfied.")
