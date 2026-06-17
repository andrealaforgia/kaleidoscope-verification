# Numeric-attribute emitter — official OpenTelemetry Python SDK ONLY.
# Iteration 3: checkouts carrying payment.amount as a real NUMERIC attribute across
# a DIGIT-BOUNDARY spread (9, 90, 100, 250, 1500) so a numeric >= threshold is a
# genuine test, not a lexical one ("9" sorts above "100" as strings). Each checkout
# also carries customer.id. Prints a report mapping amount -> trace id.
import json, os, time
from opentelemetry import trace
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import SimpleSpanProcessor
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter

ENDPOINT = os.environ["OTEL_HTTP_ENDPOINT"].rstrip("/")
SERVICE = os.environ.get("NUM_SERVICE", "bea-shop")
# digit-boundary spread: 9 and 90 are BELOW 100 but sort ABOVE "100"/"250" lexically,
# so >=100 returning exactly {100,250,1500} and excluding {9,90} proves numeric, not string.
AMOUNTS = [int(a) for a in os.environ.get("NUM_AMOUNTS", "9,90,100,250,1500").split(",")]

p = TracerProvider(resource=Resource.create({"service.name": SERVICE}))
p.add_span_processor(SimpleSpanProcessor(OTLPSpanExporter(endpoint=ENDPOINT + "/v1/traces")))
trace.set_tracer_provider(p)
t = trace.get_tracer("numeric")

report = {"service": SERVICE, "amounts": AMOUNTS, "by_amount": {}}
for amt in AMOUNTS:
    with t.start_as_current_span("POST /api/v1/checkout") as s:
        s.set_attribute("payment.amount", amt)   # NUMERIC (int) attribute, not a string
        s.set_attribute("customer.id", "bea-test")
        report["by_amount"][str(amt)] = format(s.context.trace_id, "032x")
        time.sleep(0.004)

p.force_flush(); p.shutdown()
print("NUM_REPORT=" + json.dumps(report))
