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
FIFO="$(mktemp -u)"
TOKEN="regression-test-token-$$"
MOCK_PID=""
RUNNER_PID=""

cleanup() {
  [ -n "$RUNNER_PID" ] && kill "$RUNNER_PID" 2>/dev/null || true
  [ -n "$MOCK_PID" ] && kill "$MOCK_PID" 2>/dev/null || true
  exec 3>&- 2>/dev/null || true
  rm -f "$PORT_FILE" "$STDOUT_FILE" "$FIFO"
}
trap cleanup EXIT

# Wait for an actual outcome (the port file becoming non-empty), not a fixed
# sleep -- the poll cadence below is just the check interval, not a guess at
# how long startup takes.
export MOCK_EXPECTED_AUTH="Bearer $TOKEN"
python3 "$SCRIPT_DIR/mock-mcp-server.py" >"$PORT_FILE" &
MOCK_PID=$!

for _ in $(seq 1 40); do
  [ -s "$PORT_FILE" ] && break
  sleep 0.25
done
PORT="$(cat "$PORT_FILE")"
if [ -z "$PORT" ]; then
  echo "mock MCP server never printed a port" >&2
  exit 1
fi

# Feed the runner over a FIFO we hold open explicitly, rather than a subshell
# that closes stdin after a fixed sleep -- mcp-remote appears to start
# shutting down as soon as it sees stdin EOF, without waiting for an
# in-flight response, so closing the pipe on a timer raced the real network
# round trip (flaky in CI, passed locally by luck). We keep the FIFO open
# for exactly as long as it takes to see the expected response, decided by
# polling $STDOUT_FILE below -- never by sleeping a fixed duration and
# hoping the response has landed by then.
mkfifo "$FIFO"
export REGRESSION_TEST_TOKEN="$TOKEN"
timeout 20 "$RUNNER" "http://127.0.0.1:$PORT/mcp" "Authorization" "Bearer " "REGRESSION_TEST_TOKEN" "required" <"$FIFO" >"$STDOUT_FILE" &
RUNNER_PID=$!

exec 3>"$FIFO"
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"regression-test","version":"0.1"}}}' >&3
printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}' >&3
printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' >&3

for _ in $(seq 1 76); do
  grep -q '"id":2' "$STDOUT_FILE" 2>/dev/null && break
  kill -0 "$RUNNER_PID" 2>/dev/null || break
  sleep 0.25
done

exec 3>&-
kill "$RUNNER_PID" 2>/dev/null || true
wait "$RUNNER_PID" 2>/dev/null || true
RUNNER_PID=""

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
