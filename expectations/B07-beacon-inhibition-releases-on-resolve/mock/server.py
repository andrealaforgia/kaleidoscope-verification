# B07 query-AWARE mock: the instant-query backend answers per the `query`
# param so X and Y can diverge, plus the webhook catcher.
#   - X's query (contains "up"): Active for the first FIRING_WINDOW
#     seconds, then Inactive (X fires, then resolves).
#   - Y's query (contains "latency"): Active throughout (Y stays Active,
#     suppressed while X fires, released when X resolves).
# POST records {path, body} for delivery-order assertions.
import json, os, time, http.server, socketserver
from urllib.parse import urlparse, parse_qs

START = time.time()
FIRING_WINDOW = float(os.environ.get("FIRING_WINDOW", "5"))
OUT = "/out/incidents.ndjson"

def active_for(query: str) -> bool:
    if "up" in query:                       # X: flips inactive after the window
        return (time.time() - START) < FIRING_WINDOW
    return True                             # Y (latency): always active

class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        q = parse_qs(urlparse(self.path).query).get("query", [""])[0]
        result = [{"metric": {"__name__": "x"}, "value": [0, "1"]}] if active_for(q) else []
        body = json.dumps({"status": "success",
                           "data": {"resultType": "vector", "result": result}}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        data = self.rfile.read(n).decode("utf-8", "replace")
        with open(OUT, "a") as f:
            f.write(json.dumps({"t": round(time.time() - START, 2), "body": json.loads(data)}) + "\n")
        self.send_response(200)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def log_message(self, *a):
        pass

socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(("0.0.0.0", 18091), H) as s:
    s.serve_forever()
