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
# starts the child. Remote HTTP servers run through `mcp-remote` via the
# `remoteRunner` wrapper below, which materializes the auth header into a
# 0600 temp file from the environment (`--header-file`) -- token values never
# appear in argv, where `ps` would expose them to every local user.
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
    # mcp-searxng (ihor-sokoliuk) talks to the self-hosted SearXNG instance
    # (nix-server modules/containers/searxng.nix), which publishes its JSON
    # search endpoint to nix-server's loopback at 18095 -- same
    # loopback-resolves-on-nix-server reasoning as n8n above. No auth: the
    # port is loopback-only and SearXNG has no API token, just the unrelated
    # Flask session secret (SEARXNG_SECRET).
    searxng = {
      command = "npx";
      args = [
        "-y"
        "mcp-searxng"
      ];
      env.SEARXNG_URL = "http://127.0.0.1:18095";
    };
    # camofox-mcp (redf0x1) talks to the camofox-browser container
    # (nix-server modules/containers/camofox-browser.nix), a Camoufox-based
    # anti-detection browser, published to nix-server's loopback at 18096 --
    # same loopback-resolves-on-nix-server reasoning as searxng above. No
    # auth: the server disables it for this loopback-only deployment.
    camofox = {
      command = "npx";
      args = [
        "-y"
        "camofox-mcp@latest"
      ];
      env.CAMOFOX_URL = "http://127.0.0.1:18096";
    };
  };

  # Env-only transport for remote servers. The runner's argv carries only the
  # URL, header name, header prefix, and env-var *name* -- all public -- while
  # the token *value* travels via the process environment (populated by mcpm
  # from this server's `env` dict) into a 0600 header file passed via
  # mcp-remote's `--header-file` flag (its documented workaround for argv
  # snooping: one `Name: value` per line). Token values never appear in argv,
  # where `ps` would expose them to every local user (evidence: paseo session
  # 66521186 leaked ghp_, sk-or-v1-, ctx7sk- via `ps aux | grep mcpm`).
  # The temp file is removed after the child exits; a trap covers signals.
  #
  # `\${VAR}` renders the literal ${VAR} for resolution at spawn -- never
  # resolved by Nix, never written to the store.
  remoteRunner = pkgs.writeShellScript "mcp-remote-runner" ''
    set -eu
    url="$1"; header_name="$2"; header_prefix="$3"; header_var="$4"; required="$5"
    if [ -z "$header_var" ]; then
      exec npx -y mcp-remote "$url"
    fi
    if [ -z "''${!header_var:-}" ]; then
      if [ "$required" = required ]; then
        echo "mcp-remote-runner: $header_var is unset or empty" >&2
        exit 1
      fi
      exec npx -y mcp-remote "$url"
    fi
    header_file="$(mktemp)"
    chmod 600 "$header_file"
    printf '%s: %s%s\n' "$header_name" "$header_prefix" "''${!header_var}" > "$header_file"
    trap 'rm -f "$header_file"' EXIT INT TERM
    npx -y mcp-remote "$url" --header-file "$header_file" &
    child=$!
    wait "$child"
    status=$?
    rm -f "$header_file"
    trap - EXIT INT TERM
    exit "$status"
  '';

  # Render one catalog entry to an mcpm STDIOServerConfig in the fixed `all`
  # aggregate.
  renderServer =
    name: s:
    let
      transport =
        if s ? url then
          {
            command = "${remoteRunner}";
            args = [
              s.url
              (s.headerName or "")
              (s.headerPrefix or "")
              (s.headerVar or "")
              (if s.headerRequired or true then "required" else "optional")
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
