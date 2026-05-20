# Adding an MCP Server

This repo manages MCP server configuration via Nix home-manager modules. There are two places to register an MCP server depending on scope.

## Claude Code only → `modules/claude-code.nix`

Add an entry to `programs.claude-code.mcpServers`:

```nix
programs.claude-code = {
  # ...existing config...
  mcpServers = {
    my-server = {
      command = "my-binary";
      args = [ "mcp" ];
    };
  };
};
```

This writes to Claude Code's `settings.json` under `mcpServers` (requires `enableMcpIntegration = true`, which is already set).

## Shared across tools → `modules/mcp.nix`

Add an entry to `programs.mcp.servers`:

```nix
programs.mcp.servers = {
  my-server = {
    command = "my-binary";
    args = [ "serve" ];
  };
  # HTTP servers use type + url instead of command:
  my-http-server = {
    type = "http";
    url = "https://example.com/mcp";
  };
};
```

Use `env` for environment variables and `requireEnv` (defined at the top of `mcp.nix`) for secrets that must be present at build time.

## After editing

Changes take effect after the consuming host runs `nixos-rebuild switch` or `home-manager switch`. No separate `mcp.json` file needs to be created — Nix generates it.
