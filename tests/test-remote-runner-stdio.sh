#!/usr/bin/env bash
# Regression test for nix-components 2741322: mcp-remote used to be
# backgrounded (`... &` + `wait "$child"`) in remoteRunner's header-file
# branch (modules/lib/mcp.nix), to allow cleaning up the header file
# afterward. That corrupted the stdio pipe FastMCPProxy reads tools/list
# from -- the remote connection itself always succeeded, so nothing failed
# loudly. It silently broke every server on that code path (github,
# context7, n8n, openrouter, and cloudflare on arrival) in production for
# over a week before anyone noticed.
#
# This drives the real, built remoteRunner script ($1) against a local mock
# MCP server and asserts a tools/list response actually comes back over
# stdio, so a reintroduction of that bug -- or any other change that breaks
# the stdio relay -- fails CI instead of silently reaching production.
set -euo pipefail

RUNNER="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT_FILE="$(mktemp)"
STDOUT_FILE="$(mktemp)"
TOKEN="regression-test-token-$$"
MOCK_PID=""

cleanup() {
  [ -n "$MOCK_PID" ] && kill "$MOCK_PID" 2>/dev/null || true
  rm -f "$PORT_FILE" "$STDOUT_FILE"
}
trap cleanup EXIT

export MOCK_EXPECTED_AUTH="Bearer $TOKEN"
python3 "$SCRIPT_DIR/mock-mcp-server.py" >"$PORT_FILE" &
MOCK_PID=$!

for _ in $(seq 1 20); do
  [ -s "$PORT_FILE" ] && break
  sleep 0.25
done
PORT="$(cat "$PORT_FILE")"
if [ -z "$PORT" ]; then
  echo "mock MCP server never printed a port" >&2
  exit 1
fi

export REGRESSION_TEST_TOKEN="$TOKEN"
{
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"regression-test","version":"0.1"}}}'
  sleep 2
  printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}'
  sleep 1
  printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
  sleep 3
} | timeout 20 "$RUNNER" "http://127.0.0.1:$PORT/mcp" "Authorization" "Bearer " "REGRESSION_TEST_TOKEN" "required" >"$STDOUT_FILE"

if ! grep -q '"id":1' "$STDOUT_FILE" || ! grep -q '"id":2' "$STDOUT_FILE"; then
  echo "remoteRunner did not relay both JSON-RPC responses over stdio -- this is exactly the 2741322 regression shape:" >&2
  cat "$STDOUT_FILE" >&2
  exit 1
fi

if ! grep -q 'mock_test_tool' "$STDOUT_FILE"; then
  echo "tools/list response did not include the expected marker tool:" >&2
  cat "$STDOUT_FILE" >&2
  exit 1
fi

echo "remoteRunner correctly relayed initialize + tools/list over stdio."
