{ lib, pkgs }:
# One flat server catalog rendered into mcpm's global registry
# (~/.config/mcpm/servers.json). mcpm aggregates every server tagged `active`
# behind a single stdio endpoint (`mcpm profile run active`), so each agent
# needs just one static MCP entry and no binary wrapper. Profiles are plain
# tags on servers -- see modules/mcp.nix for how `active` membership is set at
# deploy time and swapped at runtime.
#
# Secrets never land in servers.json. Each server declares the runtime
# environment references it needs. MCPM resolves only those variables when it
# starts the child. Remote HTTP servers run through `mcp-remote`, wrapped in
# `bash -c` so the child shell expands the resolved token.
let
  # A server is either stdio (`command`/`args`/`env`) or remote (`url` plus an
  # optional auth header). `profiles` are the group tags it carries.
  catalog = {
    nixos = {
      profiles = [ "core" ];
      command = "uvx";
      args = [ "mcp-nixos" ];
      # uvx otherwise downloads its own dynamically-linked CPython, which can't
      # run on NixOS without nix-ld. Point it at a nixpkgs Python instead.
      env.UV_PYTHON = "${pkgs.python3}/bin/python3";
    };
    playwright = {
      profiles = [ "core" ];
      command = "${pkgs.playwright-mcp}/bin/playwright-mcp";
      args = [
        "--headless"
        "--isolated"
      ];
    };

    github = {
      profiles = [ "core" ];
      url = "https://api.githubcopilot.com/mcp/";
      headerName = "Authorization";
      headerPrefix = "Bearer ";
      headerVar = "GITHUB_MCP_TOKEN";
      env.GITHUB_MCP_TOKEN = "\${GITHUB_MCP_TOKEN}";
    };

    context7 = {
      profiles = [ "core" ];
      # The plain /mcp endpoint works unauthenticated; the API key only raises
      # the rate limit, so the header is optional -- emitted only when the var
      # is set.
      url = "https://mcp.context7.com/mcp";
      headerName = "Context7-API-Key";
      headerVar = "CONTEXT7_API_KEY";
      headerRequired = false;
      env.CONTEXT7_API_KEY = "\${CONTEXT7_API_KEY}";
    };
    openrouter = {
      # OAuth-only; no static secret. mcp-remote drives the OAuth flow, which
      # can't complete headless -- kept for parity with the extras group.
      profiles = [ "extras" ];
      url = "https://mcp.openrouter.ai/mcp";
    };

    todoist = {
      profiles = [ "productivity" ];
      command = "npx";
      args = [
        "-y"
        "@abhiz123/todoist-mcp-server"
      ];
      env.TODOIST_API_TOKEN = "\${TODOIST_API_TOKEN}";
    };
    obsidian = {
      profiles = [ "productivity" ];
      command = "npx";
      args = [
        "-y"
        "obsidian-mcp@2"
        "serve"
        "--vault"
        "main=/var/lib/obsidian-sync/vault"
      ];
    };

    # Server-infra tooling. n8n talks to the n8n container on nix-server over
    # loopback -- off by default everywhere; only the host running that
    # container enables the `server` profile.
    n8n = {
      profiles = [ "server" ];
      url = "http://127.0.0.1:3000/mcp";
      headerName = "Authorization";
      headerPrefix = "Bearer ";
      headerVar = "N8N_MCP_AUTH_TOKEN";
      env.N8N_MCP_AUTH_TOKEN = "\${N8N_MCP_AUTH_TOKEN}";
    };
  };

  # `\${VAR}` renders the literal ${VAR} for bash to expand at spawn -- never
  # resolved by Nix, never written to the store.
  remoteCommand =
    s:
    let
      value = "${s.headerPrefix or ""}\${${s.headerVar}}";
      withHeader = "exec npx -y mcp-remote ${s.url} --header \"${s.headerName}: ${value}\"";
      withoutHeader = "exec npx -y mcp-remote ${s.url}";
    in
    if !(s ? headerName) then
      withoutHeader
    else if s.headerRequired or true then
      withHeader
    else
      "if [ -n \"\${${s.headerVar}}\" ]; then ${withHeader}; else ${withoutHeader}; fi";

  # Render one catalog entry to an mcpm STDIOServerConfig. `active` decides
  # whether it also carries the `active` tag the aggregator serves.
  renderServer =
    name: s: active:
    let
      transport =
        if s ? url then
          {
            command = "bash";
            args = [
              "-c"
              (remoteCommand s)
            ];
          }
        else
          {
            inherit (s) command;
            args = s.args or [ ];
          };
      envAttr = lib.optionalAttrs (s ? env && s.env != { }) { inherit (s) env; };
    in
    transport
    // envAttr
    // {
      inherit name;
      profile_tags = s.profiles ++ lib.optional active "active";
    };
in
{
  inherit catalog;

  # Every profile name known to the catalog plus any host-local extra servers.
  profileNames =
    extraServers: lib.unique (lib.concatMap (s: s.profiles) (lib.attrValues (catalog // extraServers)));

  # servers.json content: the catalog (plus host-local extraServers) rendered
  # to mcpm's schema, tagging `active` every server in an enabled profile.
  serverConfigs =
    {
      activeProfiles,
      extraServers ? { },
    }:
    lib.mapAttrs (name: s: renderServer name s (lib.any (p: lib.elem p activeProfiles) s.profiles)) (
      catalog // extraServers
    );
}
