---
name: add-mcp
description: Add a new MCP server to the nix-components claude-code.nix module. Use when the user wants to connect a new MCP server to Claude Code.
user-invocable: true
---

Add a new MCP server to the nix-components claude-code.nix module.

Steps:
1. Ask the user: "What should this MCP server be called?" (e.g. "context7", "paseo")
2. Ask the user: "What is the documentation URL for this MCP server?"
3. Fetch the docs URL. Find the exact connection config for Claude Code or a generic HTTP/stdio entry.
   Determine the correct Nix format:
   - stdio:       `{ command = "..."; args = [ "..." ]; }`
   - HTTP+apikey: `{ type = "http"; url = "https://..."; }` with a `headers` attrset if needed — use `requireEnv "VAR_NAME"` for secrets (see mcp.nix for the pattern)
   - HTTP+OAuth:  `{ type = "http"; url = "https://.../oauth"; }` (no headers needed)
4. Open ~/paseo-projects/nix-components/modules/claude-code.nix and add the entry inside `programs.claude-code.mcpServers = { ... };`
5. Also update ~/paseo-projects/nix-components/docs/adding-mcp.md if anything about the process is new or worth noting.
6. Commit the change with a short message and push.
7. Tell the user what was added and remind them to run nixos-rebuild / home-manager switch for it to take effect.
