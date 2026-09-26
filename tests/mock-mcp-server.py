#!/usr/bin/env python3
"""Minimal MCP Streamable HTTP server for testing remoteRunner's stdio relay.

Speaks just enough of the 2025-06-18 Streamable HTTP transport for
mcp-remote to complete initialize + tools/list: a session id header and an
SSE-framed JSON-RPC response body. Exists to catch a regression like
nix-components 2741322 (backgrounding mcp-remote corrupted the stdio pipe)
without depending on a real third-party MCP server or network access
beyond loopback. mcp-remote also probes with a GET for a persistent SSE
stream, which this server doesn't implement (501) -- harmless: mcp-remote
falls back to POST-only and the exchange below still completes.

Prints its bound port to stdout on startup, then serves until killed.
"""

import http.server
import json
import os

EXPECTED_AUTH = os.environ.get("MOCK_EXPECTED_AUTH")
TOOL_NAME = "mock_test_tool"


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass  # keep CI logs quiet; failures are asserted by the caller

    def do_POST(self):
        if self.path != "/mcp":
            self.send_response(404)
            self.end_headers()
            return

        if (
            EXPECTED_AUTH is not None
            and self.headers.get("Authorization") != EXPECTED_AUTH
        ):
            self.send_response(401)
            self.end_headers()
            return

        length = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(length)) if length else {}
        method = body.get("method")

        if method == "notifications/initialized":
            self.send_response(202)
            self.end_headers()
            return

        if method == "initialize":
            result = {
                "protocolVersion": "2025-06-18",
                "capabilities": {"tools": {"listChanged": True}},
                "serverInfo": {"name": "mock-mcp-server", "version": "0.0.0"},
            }
        elif method == "tools/list":
            result = {
                "tools": [
                    {
                        "name": TOOL_NAME,
                        "description": "Regression-test marker tool.",
                        "inputSchema": {"type": "object", "properties": {}},
                    }
                ]
            }
        else:
            self.send_response(400)
            self.end_headers()
            return

        response = {"jsonrpc": "2.0", "id": body.get("id"), "result": result}
        payload = f"event: message\ndata: {json.dumps(response)}\n\n".encode()

        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Mcp-Session-Id", "mock-session-0000")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        self.wfile.write(payload)


def main():
    server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
    print(server.server_port, flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
