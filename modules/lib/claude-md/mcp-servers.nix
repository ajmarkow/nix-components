''
  ## MCP Servers

  **Always check `mcpm` first for tools that can handle the request.** This applies even when a native connector, Codex app, or installable plugin exists for the same service. Search the tools exposed by `mcpm` before you use or suggest another integration. Do not assume a tool is unavailable only because it is not in the initial tool list; use tool discovery to look for the matching `mcpm` tool. For example, Todoist work must first use the Todoist tools exposed through `mcpm`, not the native Todoist connector or Codex app.

  **Call MCP tools only through the single `mcpm` aggregator.** Tool names include the underlying server name, such as `<server>_<tool>` or `mcp__mcpm__<server>_<tool>` (for example, `nixos_nix` or `mcp__mcpm__todoist_find_tasks`). Use a native connector, Codex app, or plugin only when explicit `mcpm` tool discovery finds no usable tool for the service. Every agent on every host points at the central tailnet endpoint `https://mcpm.tail772f0.ts.net/mcp`, served from nix-server. The registry holds env-var names, never secret values.

  **Never edit the central registry by hand.** Add servers in `modules/lib/mcp.nix` in nix-components, then redeploy nix-server so its `mcpm` service picks them up. Start a new session after — servers connect at session start.
''
