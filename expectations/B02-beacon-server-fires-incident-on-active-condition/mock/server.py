# B02 mock: doubles as the PromQL instant-query backend AND the webhook
# sink catcher. GET (any path, beacon hits /api/v1/query) returns a
# Prometheus instant-query response: a NON-EMPTY vector for the first
# FIRING_WINDOW seconds (drives beacon Active -> Firing), then an EMPTY
# vector (drives Active -> Inactive -> Resolved). POST (beacon's webhook
# sink) appends the raw Incident JSON to /out/incidents.ndjson.
import json, os, time, http.server, socketserver

START = time.time()
FIRING_WINDOW = float(os.environ.get("FIRING_WINDOW", "5"))
OUT = "/out/incidents.ndjson"

class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        firing = (time.time() - START) < FIRING_WINDOW
        result = [{"metric": {"__name__": "up"}, "value": [0, "1"]}] if firing else []
        body = json.dumps({"status": "success",
                           "data": {"resultType": "vector", "result": result}}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        data = self.rfile.read(n)
        with open(OUT, "ab") as f:
            f.write(data + b"\n")
        self.send_response(200)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def log_message(self, *a):
        pass

socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(("0.0.0.0", 18091), H) as s:
    s.serve_forever()
