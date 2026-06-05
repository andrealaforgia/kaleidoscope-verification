# B05 mock: Active PromQL instant-query backend on GET; webhook catcher on
# POST that records the REQUEST PATH alongside the body, so the runner can
# assert that one incident reached MULTIPLE distinct sink endpoints.
import json, time, http.server, socketserver
OUT = "/out/incidents.ndjson"

class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = json.dumps({"status": "success",
                           "data": {"resultType": "vector",
                                    "result": [{"metric": {"__name__": "up"}, "value": [0, "1"]}]}}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        data = self.rfile.read(n).decode("utf-8", "replace")
        with open(OUT, "a") as f:
            f.write(json.dumps({"path": self.path, "body": json.loads(data)}) + "\n")
        self.send_response(200)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def log_message(self, *a):
        pass

socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(("0.0.0.0", 18091), H) as s:
    s.serve_forever()
