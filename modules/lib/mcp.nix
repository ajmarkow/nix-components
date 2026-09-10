{
  lib,
  pkgs,
  homeDirectory,
}:
# One flat server catalog rendered into mcpm's global registry
# (~/.config/mcpm/servers.json). mcpm aggregates every server tagged `all`
# behind one HTTP endpoint (`mcpm profile run --http all`), served centrally
# from nix-server and pointed at by every agent on every host. `all` is a
# fixed MCPM implementation detail, not a selectable profile.
#
# Secrets never land in servers.json. Each server declares the runtime
# environment references it needs. MCPM resolves only those variables when it
# starts the child. Remote HTTP servers run through `mcp-remote`, wrapped in
# `bash -c` so the child shell expands the resolved token.
let
  # mcpm launches each mounted server with exactly the `env` dict from
  # servers.json -- it does not inherit or merge the parent process's
  # environment, so systemd-level Environment= (modules/mcp.nix) never
  # reaches these subprocesses; only entries here do. npx/uvx default their
  # package caches to $HOME, which the mcpm service sandboxes
  # read-only, so every npx/uvx-based server must redirect its cache here
  # explicitly. Pointed at a path under the real home directory (added to
  # that service's ReadWritePaths) rather than /tmp: PrivateTmp tears down
  # and recreates /tmp on every service restart/redeploy, which previously
  # forced every server to re-fetch its packages from scratch each time --
  # several minutes of cold start before tools/list even returned.
  cacheEnv = {
    NPM_CONFIG_CACHE = "${homeDirectory}/.cache/mcpm/npm";
    # mcp-remote persists OAuth client registration and tokens here, defaulting
    # to ~/.mcp-auth -- read-only under the mcpm service. Nothing writes it
    # while the static bearer headers work, but a 401 falls back to the OAuth
    # flow, which would then fail on an unwritable path.
    MCP_REMOTE_CONFIG_DIR = "${homeDirectory}/.cache/mcpm/mcp-auth";
    UV_CACHE_DIR = "${homeDirectory}/.cache/mcpm/uv";
    # uvx also installs tool environments (separate from its download cache)
    # under XDG_DATA_HOME/uv/tools by default -- redirect that too.
    UV_TOOL_DIR = "${homeDirectory}/.cache/mcpm/uv-tools";
  };

  # A server is either stdio (`command`/`args`/`env`) or remote (`url` plus an
  # optional auth header). Every entry joins the fixed `all` aggregate.
  catalog = {
    nixos = {
      command = "uvx";
      args = [ "mcp-nixos" ];
      # uvx otherwise downloads its own dynamically-linked CPython, which can't
      # run on NixOS without nix-ld. Point it at a nixpkgs Python instead.
      env.UV_PYTHON = "${pkgs.python3}/bin/python3";
    };
    playwright = {
      command = "${pkgs.playwright-mcp}/bin/playwright-mcp";
      args = [
        "--headless"
        "--isolated"
        # Default output dir is <cwd>/.playwright-mcp, and the server inherits
        # cwd $HOME from the mcpm service, whose ProtectHome=read-only makes
        # that path unwritable -- every screenshot and spilled snapshot failed
        # with EROFS. This subtree is already in the unit's ReadWritePaths.
        "--output-dir"
        "${homeDirectory}/.cache/mcpm/playwright"
      ];
    };

    github = {
      url = "https://api.githubcopilot.com/mcp/";
      headerName = "Authorization";
      headerPrefix = "Bearer ";
      headerVar = "GITHUB_MCP_TOKEN";
      env.GITHUB_MCP_TOKEN = "\${GITHUB_MCP_TOKEN}";
    };

    context7 = {
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
      # Static bearer key from opencode.env (OPENROUTER_API_KEY). Without
      # it mcp-remote falls back to an OAuth browser flow that can never
      # complete headless, hanging the whole aggregate's tools/list.
      url = "https://mcp.openrouter.ai/mcp";
      headerName = "Authorization";
      headerPrefix = "Bearer ";
      headerVar = "OPENROUTER_API_KEY";
      env.OPENROUTER_API_KEY = "\${OPENROUTER_API_KEY}";
    };

    todoist = {
      command = "npx";
      args = [
        "-y"
        "@doist/todoist-mcp"
      ];
      # @doist/todoist-mcp reads TODOIST_API_KEY; nix-server's secrets
      # pipeline (todoist-mcp.env) still exports the token as
      # TODOIST_API_TOKEN, so the template on the right stays unchanged.
      env.TODOIST_API_KEY = "\${TODOIST_API_TOKEN}";
    };
    obsidian = {
      command = "npx";
      args = [
        "-y"
        "obsidian-mcp@2"
        "serve"
        "--vault"
        "agentic=/var/lib/obsidian-sync/vault"
      ];
    };

    # Server-infra tooling. The loopback URL resolves on nix-server, where both
    # mcpm and the n8n container run. Every tailnet client reaches it through
    # the central aggregate -- no host-local setup needed anywhere else.
    n8n = {
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

  # Render one catalog entry to an mcpm STDIOServerConfig in the fixed `all`
  # aggregate.
  renderServer =
    name: s:
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
      envAttr = {
        env = cacheEnv // (s.env or { });
      };
    in
    transport
    // envAttr
    // {
      inherit name;
      profile_tags = [ "all" ];
    };
in
{
  inherit catalog;

  # servers.json content: the whole catalog (plus host-local extraServers)
  # rendered to mcpm's schema, every server in the fixed `all` aggregate.
  serverConfigs =
    {
      extraServers ? { },
    }:
    lib.mapAttrs renderServer (catalog // extraServers);
}
