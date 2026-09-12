''
  ## MCP Servers

  **Call MCP tools only through the single `mcpm` aggregator.** Tool names are `<server>_<tool>` (e.g. `nixos_nix`). Every agent on every host points at the central tailnet endpoint `https://mcpm.tail772f0.ts.net/mcp`, served from nix-server. The registry holds env-var names, never secret values.

  **Never edit the central registry by hand.** Add servers in `modules/lib/mcp.nix` in nix-components, then redeploy nix-server so its `mcpm` service picks them up. Start a new session after — servers connect at session start.
''
