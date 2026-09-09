# Adding an MCP Server

MCP servers live in one flat catalog and are served to every agent (Claude
Code, Codex, opencode) through a single central `mcpm` aggregate. There are
no binary wrappers and no per-agent server definitions -- every agent points
at one fixed URL, `https://mcpm.tail772f0.ts.net/mcp`, served from nix-server
over the tailnet.

## Where servers are defined

Edit the `catalog` in `modules/lib/mcp.nix`. Each entry is one server with
its transport. Every entry joins the fixed `all` aggregate, served by
`mcpm profile run --http all` on nix-server. `all` is an MCPM implementation
detail, not something agents or users select.

### stdio server

```nix
my-server = {
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

## The central aggregate

`all` contains every catalog entry, including Todoist, Obsidian, OpenRouter,
and n8n. There are no selectable profiles and no runtime switching: the only
way to change the served set is to edit the catalog (or `extraServers`) and
redeploy nix-server.

## Host-local servers

A server that only makes sense on the server host (e.g. n8n, which talks to
a container over loopback on nix-server) goes in that host's config via
`nix-components.mcp.extraServers`, using the same entry shape as the catalog.
Its name must not collide with a built-in server. It joins `all` like
everything else, so the whole tailnet reaches it through the central
endpoint -- client hosts need no local setup or secrets.

Only server mode (`nix-components.mcp.server.enable`, nix-server's paseo user)
renders `~/.config/mcpm/servers.json` and runs the `mcpm` service.
Everywhere else `nix-components.mcp.enable` only points agents at
`nix-components.mcp.endpoint`.

## After editing

Run `nix flake check --no-build`, commit, and push. CI deploys via
home-manager; redeploying nix-server picks up the new set. No `servers.json`
is written by hand -- Nix generates it on the server.
