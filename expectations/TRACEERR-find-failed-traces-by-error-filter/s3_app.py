# Surface-3 external emitter — official OpenTelemetry Python SDK ONLY.
# Sends TWO traces under the SAME service.name in the same window:
#   - a FAILED trace: parent "POST /api/v1/checkout" with Error status, plus a
#     child span (so we can assert ALL spans of the failed trace come back), and
#   - a HEALTHY trace: parent "GET /api/v1/health" (Unset) + a child.
# Prints both trace ids so a black-box test can assert the error filter returns
# the failed trace IN FULL and EXCLUDES the healthy one.
import json
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

_captured = []


class _Capture(SpanExporter):
    def export(self, spans):
        _captured.extend(spans)
        return SpanExportResult.SUCCESS

    def shutdown(self):
        pass

    def force_flush(self, timeout_millis=30000):
        return True


resource = Resource.create({"service.name": "surface3-svc"})
provider = TracerProvider(resource=resource)
provider.add_span_processor(
    SimpleSpanProcessor(OTLPSpanExporter(endpoint=ENDPOINT + "/v1/traces"))
)
provider.add_span_processor(SimpleSpanProcessor(_Capture()))
trace.set_tracer_provider(provider)
tracer = trace.get_tracer("surface3")


def h(n, w):
    return format(n, "0%dx" % w)


report = {"failed": None, "healthy": None}

# FAILED trace — parent carries Error status; a child rides along.
with tracer.start_as_current_span("POST /api/v1/checkout") as parent:
    parent.set_status(Status(StatusCode.ERROR, "checkout failed: card declined"))
    report["failed"] = h(parent.context.trace_id, 32)
    with tracer.start_as_current_span("charge-card") as child:
        child.set_attribute("payment.declined", True)
        time.sleep(0.01)

# HEALTHY trace — no error anywhere.
with tracer.start_as_current_span("GET /api/v1/health") as ok_parent:
    report["healthy"] = h(ok_parent.context.trace_id, 32)
    with tracer.start_as_current_span("ping") as ok_child:
        time.sleep(0.01)

provider.force_flush()
provider.shutdown()

print("S3_REPORT=" + json.dumps(report))
