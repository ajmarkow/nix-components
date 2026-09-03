{ lib, pkgs }:
# One flat server catalog rendered into mcpm's global registry
# (~/.config/mcpm/servers.json). mcpm aggregates every server tagged `active`
# behind a single stdio endpoint (`mcpm profile run active`), so each agent
# needs just one static MCP entry and no binary wrapper. Profiles are plain
# tags on servers -- see modules/mcp.nix for how `active` membership is set at
# deploy time and swapped at runtime.
#
# Secrets never land in servers.json. stdio servers inherit them from the
# agent's session env (FastMCP copies os.environ into each child). Remote HTTP
# servers run as stdio through `mcp-remote`, wrapped in `bash -c` so the
# inheriting shell expands the token at spawn -- only the env-var NAME is
# stored, never its value.
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
      # TODOIST_API_TOKEN reaches the child by env inheritance -- not declared
      # here, so it never touches disk.
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
