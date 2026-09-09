# Fix: mcpm silently moves to :6277 while opencode points at :6276

Opencode declares one aggregator, `mcpm -> http://127.0.0.1:6276/mcp`
(`modules/mcp.nix:28`). The `mcpm-active-profile` service starts mcpm with
`--port 6276`. When :6276 is still held by a draining instance at restart,
mcpm falls back to :6277 without failing. Opencode keeps dialling :6276,
`opencode mcp list` shows `mcpm failed`, and the agent sees zero MCP tools.

Observed 2026-09-09 ~16:09 UTC: old instance was still draining (uvicorn
`CancelledError` traces) when the new one started; new instance served
:6277; `curl :6276/mcp` returned 000; opencode reported `failed ... Unable
to connect`.

There is no CNAME equivalent for a TCP port. The fix makes the fallback
impossible and adds a gated watchdog.

## Fix

### 1. `modules/mcp.nix` — fixed-port invariant

Find how mcpm/FastMCP auto-bumps the port and disable it. If no switch
exists, add guards instead:

- `ExecStartPre` that fails when :6276 is already bound.
- `ExecStartPost` that curls `:6276/mcp` and fails the unit unless it gets
  the expected JSON-RPC reply (a bare GET returns the
  `Not Acceptable: Client must accept text/event-stream` error body, which
  still proves the port is ours).
- `StartLimitIntervalSec` / `StartLimitBurst` so a persistent conflict
  throttles instead of hot-looping.

A conflict becomes a loud failed unit (visible in journals, retried by
systemd) instead of a silent :6277 serving nobody.

### 2. Watchdog timer — gated, no cascade

New user timer (every 60s) plus oneshot probe service: `curl :6276/mcp`,
success resets a counter file, failure increments it. Restart
`mcpm-active-profile` only after 3 consecutive failures (~3 min down), so
one blip never touches active SSE sessions. Restarts stay rare and
rate-limited via the start-limit above. Each failed probe logs a line, so
flakes are visible before action.

### 3. `pkgs/mcp-profile.nix` — root handling

Detect root / `SUDO_USER`; do not attempt the restart, print the exact
command instead:

```bash
/run/wrappers/bin/sudo -u paseo XDG_RUNTIME_DIR=/run/user/995 systemctl --user restart mcpm-active-profile
```

Stop swallowing stderr (`2>/dev/null` hid "unit not found"); surface the
real error.

### 4. Verify

```bash
cd /var/lib/paseo/paseo-projects/nix-components && nix flake check --no-build
```

Commit and push. CI deploys. After the deploy:

- `opencode mcp list` shows `mcpm` connected.
- Conflict test: hold :6276, restart the service, assert it fails loudly
  (never :6277); release, assert recovery.
- Kill test: stop the service, confirm the probe restarts it within ~3 min
  and opencode reconnects on a new session.

## Secrets

None.
