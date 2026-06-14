# PG-1 external demo app — official OpenTelemetry Python SDK ONLY.
# ZERO Kaleidoscope code. Sends a parent+child trace (and, bonus, a log
# emitted INSIDE the active span) over the real OTLP/HTTP wire, then prints a
# machine-readable report so a black-box test can retrieve-by-id and compare.
#
# Criteria exercised (PO-locked):
#   - parent + child span; child.parent_span_id == parent.span_id
#   - customer.id="bea-test" as a SPAN attribute on the child
#   - exact start/end nanos printed for round-trip comparison
#   - bonus: one log emitted inside the child span (PG-2 seed)
import json
import logging
import os
import time

from opentelemetry import trace
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import (
    SimpleSpanProcessor,
    SpanExporter,
    SpanExportResult,
)
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter

ENDPOINT = os.environ["OTEL_HTTP_ENDPOINT"].rstrip("/")  # e.g. http://rt:4318

# ---- capture the exact ReadableSpans we export (for the report) ----
_captured = []


class _Capture(SpanExporter):
    def export(self, spans):
        _captured.extend(spans)
        return SpanExportResult.SUCCESS

    def shutdown(self):
        pass

    def force_flush(self, timeout_millis=30000):
        return True


resource = Resource.create({"service.name": "pg1-external-demo"})
provider = TracerProvider(resource=resource)
provider.add_span_processor(
    SimpleSpanProcessor(OTLPSpanExporter(endpoint=ENDPOINT + "/v1/traces"))
)
provider.add_span_processor(SimpleSpanProcessor(_Capture()))
trace.set_tracer_provider(provider)
tracer = trace.get_tracer("pg1-demo")

# ---- bonus: OTel logs SDK, one log inside the active span (PG-2 seed) ----
log_ok = False
try:
    from opentelemetry.sdk._logs import LoggerProvider, LoggingHandler
    from opentelemetry.sdk._logs.export import SimpleLogRecordProcessor
    from opentelemetry.exporter.otlp.proto.http._log_exporter import OTLPLogExporter

    lp = LoggerProvider(resource=resource)
    lp.add_log_record_processor(
        SimpleLogRecordProcessor(OTLPLogExporter(endpoint=ENDPOINT + "/v1/logs"))
    )
    handler = LoggingHandler(level=logging.INFO, logger_provider=lp)
    applog = logging.getLogger("pg1-demo")
    applog.setLevel(logging.INFO)
    applog.addHandler(handler)
    log_ok = True
except Exception as exc:  # bonus is non-blocking
    print("PG1_LOG_SETUP_FAILED=" + str(exc))

with tracer.start_as_current_span("parent-op") as parent:
    time.sleep(0.01)
    with tracer.start_as_current_span("child-op") as child:
        child.set_attribute("customer.id", "bea-test")
        if log_ok:
            # emitted while child is the active span -> SDK stamps trace_id/span_id
            applog.error("pg1 external app: checkout failed for customer bea-test")
        time.sleep(0.01)

provider.force_flush()
if log_ok:
    lp.force_flush()
provider.shutdown()

# ---- report ----
def h(n, w):
    return format(n, "0%dx" % w)


report = {"trace_id": None, "parent": None, "child": None}
for s in _captured:
    report["trace_id"] = h(s.context.trace_id, 32)
    entry = {
        "name": s.name,
        "span_id": h(s.context.span_id, 16),
        "parent_span_id": (h(s.parent.span_id, 16) if s.parent else None),
        "start": s.start_time,
        "end": s.end_time,
        "attributes": {k: str(v) for k, v in (s.attributes or {}).items()},
    }
    report["child" if s.parent else "parent"] = entry

print("PG1_REPORT=" + json.dumps(report))
