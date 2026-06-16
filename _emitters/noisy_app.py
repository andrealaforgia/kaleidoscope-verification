# Noisy realistic emitter — official OpenTelemetry Python SDK ONLY.
# Emits a realistic noisy log+trace mix for iteration-2 search discrimination:
# several customers, several request types, MOSTLY successful, with exactly ONE
# customer's checkout DECLINED. Each request is a trace with an in-span log (so
# logs carry trace_id for the symptom-path pivot). The single declined checkout
# carries the "card declined" cause log at ERROR severity; everything else is INFO.
#
# Serves both iteration-2 paths and their discrimination tests:
#   - SYMPTOM: text search "declined" -> exactly the one declined log; severity
#     ERROR -> exactly the declined error log out of many INFO logs; that log
#     carries its trace_id -> pivot to where->why.
#   - IDENTIFIER (fast-follow): trace search by customer.id=bea-test -> bea-test's
#     traces only, not everyone's.
#
# Prints a machine-readable report (the declined trace id + the customer/type mix)
# so a black-box runner can assert the search picks the one failure out of noise.
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
from opentelemetry.trace import Status, StatusCode

ENDPOINT = os.environ["OTEL_HTTP_ENDPOINT"].rstrip("/")
# IMPORTANT: NOT "kaleidoscope-demo" — the runtime's demo overlay (ADR-0079, now
# default-on in the binary) SYNTHESISES extra demo traces/logs for service.name
# "kaleidoscope-demo", which would inject a SECOND declined record and contaminate
# the discrimination test. Use a non-demo service so the overlay passes through and
# the noisy mix is exactly what this emitter produces (one declined = bea-test).
SERVICE = os.environ.get("NOISY_SERVICE", "bea-shop")

_captured = []


class _Capture(SpanExporter):
    def export(self, spans):
        _captured.extend(spans)
        return SpanExportResult.SUCCESS

    def shutdown(self):
        pass

    def force_flush(self, timeout_millis=30000):
        return True


resource = Resource.create({"service.name": SERVICE})
provider = TracerProvider(resource=resource)
provider.add_span_processor(SimpleSpanProcessor(OTLPSpanExporter(endpoint=ENDPOINT + "/v1/traces")))
provider.add_span_processor(SimpleSpanProcessor(_Capture()))
trace.set_tracer_provider(provider)
tracer = trace.get_tracer("noisy")

from opentelemetry.sdk._logs import LoggerProvider, LoggingHandler
from opentelemetry.sdk._logs.export import SimpleLogRecordProcessor
from opentelemetry.exporter.otlp.proto.http._log_exporter import OTLPLogExporter

lp = LoggerProvider(resource=resource)
lp.add_log_record_processor(SimpleLogRecordProcessor(OTLPLogExporter(endpoint=ENDPOINT + "/v1/logs")))
handler = LoggingHandler(level=logging.INFO, logger_provider=lp)
applog = logging.getLogger("noisy")
applog.setLevel(logging.INFO)
applog.addHandler(handler)


def h(n, w):
    return format(n, "0%dx" % w)


# Realistic noise: several customers, several request types, mostly successful.
CUSTOMERS = ["alice", "bob", "carol", "dave", "bea-test"]
TYPES = ["GET /api/v1/products", "GET /api/v1/cart", "POST /api/v1/checkout", "GET /api/v1/search"]

report = {"declined_trace": None, "declined_customer": "bea-test", "service": SERVICE,
          "customers": CUSTOMERS, "types": TYPES, "total_requests": 0, "declined_count": 0}

# The ONE declined checkout belongs to bea-test; every other request succeeds.
plan = []
for cust in CUSTOMERS:
    for t in TYPES:
        # skip some pairs to vary volume, but guarantee bea-test's checkout exists
        if cust == "bea-test" and t == "POST /api/v1/checkout":
            plan.append((cust, t, True))   # the single declined failure
        elif (hash((cust, t)) % 3) != 0:   # ~2/3 of pairs, deterministic-ish spread
            plan.append((cust, t, False))

for cust, t, declined in plan:
    with tracer.start_as_current_span(t) as span:
        span.set_attribute("customer.id", cust)
        span.set_attribute("http.route", t)
        if declined:
            span.set_status(Status(StatusCode.ERROR, "checkout failed: card declined"))
            applog.error("checkout failed: card declined", extra={"customer.id": cust})
            report["declined_trace"] = h(span.context.trace_id, 32)
            report["declined_count"] += 1
        else:
            applog.info("%s ok for customer %s" % (t, cust), extra={"customer.id": cust})
        report["total_requests"] += 1
        time.sleep(0.004)

provider.force_flush()
lp.force_flush()
provider.shutdown()

print("NOISY_REPORT=" + json.dumps(report))
