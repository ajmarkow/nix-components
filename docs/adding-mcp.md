# Adding an MCP Server

MCP servers live in one flat catalog and are served to every agent (Claude
Code, Codex, opencode) through a single `mcpm` aggregator. There are no binary
wrappers and no per-agent server definitions -- each agent points at one fixed
entry, `mcpm profile run active`, and the active set is controlled by tags in
mcpm's `servers.json`.

## Where servers are defined

Edit the `catalog` in `modules/lib/mcp.nix`. Each entry is one server with a
`profiles` list (its group tags) plus its transport.

### stdio server

```nix
my-server = {
  profiles = [ "core" ];       # one or more group tags
  command = "npx";
  args = [ "-y" "my-mcp-server" ];
  env.SOME_FLAG = "value";      # optional, non-secret only
};
```

Declare secret environment variables as runtime references. MCPM resolves only
the listed variables when it starts the server. The generated configuration
contains the variable name, not its value.

```nix
env.API_TOKEN = "\${API_TOKEN}";
```

### remote HTTP server

```nix
my-http = {
  profiles = [ "extras" ];
  url = "https://example.com/mcp";
  headerName = "Authorization";   # optional auth header
  headerPrefix = "Bearer ";       # optional prefix on the value
  headerVar = "MY_TOKEN";         # env-var NAME holding the secret
  headerRequired = true;          # false => header emitted only when set
};
```

Remote servers run as stdio through `mcp-remote`, wrapped so the inheriting
shell expands `headerVar` at spawn. Add the same runtime reference to `env` so
MCPM passes it to that shell. Only the variable **name** is stored in
`servers.json`.

## Profiles

`profiles` are plain tags. A profile is "on" when it is listed in
`nix-components.mcp.enabledProfiles` (default: `core`) -- every server in an
enabled profile gets the `active` tag, and `mcpm profile run active` aggregates
them. `core` holds the always-used dev tools (nixos, playwright, context7,
github); `productivity` (todoist, obsidian) and `extras` (openrouter) are off by
default.

Swap the active set at runtime without a rebuild:

```bash
mcp-profile core github extras productivity
```

This retags `servers.json` and takes effect on the next agent session. The
Nix-declared default returns on the next deploy.

## Host-local servers

A server that only makes sense on one host goes in that host's config via
`nix-components.mcp.extraServers`, using the same entry shape as the catalog.
Its name must not collide with a built-in server.

## After editing

Run `nix flake check --no-build`, commit, and push. CI deploys via
home-manager. No `servers.json` is written by hand -- Nix generates it.
