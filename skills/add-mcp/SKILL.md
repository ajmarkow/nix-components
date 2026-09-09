---
name: add-mcp
description: Add a new MCP server to the nix-components catalog. Use when the user wants a new MCP server available to Claude Code, Codex, and opencode.
user-invocable: true
---

Add a new MCP server to the nix-components `catalog` in `modules/lib/mcp.nix`.
Every agent on every host reaches it through the central tailnet aggregate --
no per-agent entries, no profiles to select.

Steps:

1. Ask the user: "What should this MCP server be called?" (e.g. "context7", "paseo")
2. Ask the user: "What is the documentation URL for this MCP server?"
3. Fetch the docs URL. Find the exact connection config, then map it to the catalog shape (see docs/adding-mcp.md):
   - stdio: `{ command = "..."; args = [ "..." ]; }`
   - HTTP+secret: `{ url = "https://..."; headerName = "..."; headerVar = "VAR_NAME"; }` plus `env.VAR_NAME = "\${VAR_NAME}"` so MCPM passes it to the child
   - HTTP+OAuth: `{ url = "https://..."; }` (no headers needed)
4. Open ~/paseo-projects/nix-components/modules/lib/mcp.nix and add the entry to `catalog`. Every entry joins the fixed `all` aggregate automatically.
5. Also update ~/paseo-projects/nix-components/docs/adding-mcp.md if anything about the process is new or worth noting.
6. Commit the change with a short message and push. Redeploying nix-server picks up the new server; client hosts need nothing.
