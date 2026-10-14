#!/usr/bin/env python3
"""Minimal stand-in for Ollama's /api/generate endpoint.

Lets you exercise BuaJi's full plumbing — OLLAMA_URL, the diff/review loop,
the CVE gate, and the whole sandbox wiring — without downloading a multi-GB
model or needing a working GPU. Every prompt gets the same canned reply.

    python3 scripts/mock-ollama.py [PORT]   # default 11434
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 11434


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        self.rfile.read(length)  # drain the request body
        payload = json.dumps({"response": "True (mock reviewer)"}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, *args):
        pass  # stay quiet


if __name__ == "__main__":
    print(f"mock ollama listening on 0.0.0.0:{PORT}", flush=True)
    HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
