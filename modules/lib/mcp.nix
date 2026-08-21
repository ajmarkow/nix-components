{ lib, pkgs }:
{
  # Every known profile, keyed by name, grouping one or more servers. `kind` lives on
  # each SERVER, not the profile -- a profile is just a named grouping, and
  # `productivity` mixes servers that need different delivery mechanisms. Each
  # agent's reshape function below dispatches per-server on `s.kind`, because the
  # three agents use incompatible conventions for substituting a secret into a
  # server definition: claude-code's runtime `${VAR}` expansion, opencode's
  # `{env:VAR}` convention, and codex's static `http_headers` (needing a
  # `env_http_headers` name-mapping instead of a templated value) for HTTP servers.
  # A single shared shape cannot serve all three, so each server declares just the
  # facts (url/command, header name, which env var holds the secret) and each
  # reshape function renders its own agent-correct form from those facts.
  profiles = {
    core = {
      servers = {
        nixos = {
          kind = "plain";
          command = "uvx";
          args = [ "mcp-nixos" ];
          # uvx defaults to downloading its own dynamically-linked CPython build,
          # which can't run on NixOS without nix-ld. Point it at a nixpkgs Python
          # instead so it works on every host without extra system config.
          env = { UV_PYTHON = "${pkgs.python3}/bin/python3"; };
        };
        playwright = {
          kind = "plain";
          command = "${pkgs.playwright-mcp}/bin/playwright-mcp";
          args = [ "--headless" "--isolated" ];
        };
      };
    };

    github = {
      servers.github = {
        kind = "auth-http";
        url = "https://api.githubcopilot.com/mcp/";
        headerName = "Authorization";
        envVar = "GITHUB_MCP_TOKEN";
        valuePrefix = "Bearer ";
      };
    };

    context7 = {
      servers.context7 = {
        kind = "auth-http";
        # The /mcp/oauth endpoint requires an interactive OAuth flow that never
        # completes for a non-interactive session. The plain /mcp endpoint works
        # fully unauthenticated and additionally accepts an API key header for a
        # higher rate limit -- no OAuth involved either way.
        url = "https://mcp.context7.com/mcp";
        headerName = "Context7-API-Key";
        envVar = "CONTEXT7_API_KEY";
        valuePrefix = "";
      };
    };

    # OpenRouter MCP -- model catalog, credit lookup, live benchmarks, and test
    # inference. Uses browser OAuth on first connect; no static API key needed.
    # Activate explicitly: `mcp-profile openrouter` (or add to enabledProfiles).
    openrouter = {
      servers.openrouter = {
        kind = "oauth-http";
        url = "https://mcp.openrouter.ai/mcp";
      };
    };

    # Personal-workflow tooling -- deliberately excluded from the `full` profile
    # set: not something every general coding session should connect to by
    # default. Activate explicitly: `mcp-profile productivity`.
    productivity = {
      servers = {
        todoist = {
          # Secret delivered via a spawned subprocess's env, not an HTTP header --
          # a third delivery mechanism alongside plain/auth-http.
          kind = "auth-stdio";
          command = "npx";
          args = [ "-y" "@abhiz123/todoist-mcp-server" ];
          # Static personal API token from Todoist Settings -> Integrations ->
          # Developer. NOT the official @doist/todoist-mcp, which is OAuth-only
          # and doesn't fit a Nix-declared static secret.
          envVar = "TODOIST_API_TOKEN";
        };
        # Filesystem-direct, NOT the REST-API-plugin server (`mcp-obsidian`) --
        # the plugin route needs the real Obsidian Electron app running somewhere
        # reachable, which the official `obsidian-headless` sync tool (separate
        # nix-server infrastructure, not part of this repo) does not provide. No
        # secret needed -- this just reads local files once the vault is synced
        # onto the host at the path below.
        obsidian = {
          kind = "plain";
          command = "npx";
          args = [ "-y" "obsidian-mcp@2" "serve" "--vault" "main=/var/lib/obsidian-sync/vault" ];
        };
      };
    };
  };

  # Reshape functions: one per agent's native schema, applied to a single
  # profile's servers, dispatching per-server on `s.kind`. Pre-rendered into one
  # fragment file per profile per agent (modules/mcp.nix) -- never called with
  # more than one profile's servers at once; combining profiles happens by
  # merging already-rendered fragments (jq/concatenation), not by merging Nix
  # data, so a fresh profile can be added without touching this merge logic.
  toClaudeCodeFragment =
    profile:
    {
      mcpServers = lib.mapAttrs (
        _: s:
        if s.kind == "plain" then
          { command = s.command; args = s.args; } // (lib.optionalAttrs (s ? env) { env = s.env; })
        else if s.kind == "auth-http" then
          {
            type = "http";
            url = s.url;
            # Literal ${VAR}, expanded by claude-code from its own process env at
            # its own runtime -- never resolved by Nix, never written to the store.
            headers.${s.headerName} = "${s.valuePrefix}\${${s.envVar}}";
          }
        else if s.kind == "oauth-http" then
          {
            type = "http";
            url = s.url;
          }
        else
          {
            # auth-stdio
            command = s.command;
            args = s.args;
            env.${s.envVar} = "\${${s.envVar}}";
          }
      ) profile.servers;
    };

  toOpencodeFragment =
    profile:
    {
      mcp = lib.mapAttrs (
        _: s:
        if s.kind == "plain" then
          { type = "local"; command = [ s.command ] ++ s.args; }
          // (lib.optionalAttrs (s ? env) { environment = s.env; })
        else if s.kind == "auth-http" then
          {
            type = "remote";
            url = s.url;
            # opencode's own documented convention -- distinct from claude-code's.
            headers.${s.headerName} = "${s.valuePrefix}{env:${s.envVar}}";
          }
        else if s.kind == "oauth-http" then
          {
            type = "remote";
            url = s.url;
          }
        else
          {
            # auth-stdio
            type = "local";
            command = [ s.command ] ++ s.args;
            environment.${s.envVar} = "{env:${s.envVar}}";
          }
      ) profile.servers;
    };

  # Raw TOML text, not a Nix attrset -- codex's active file is assembled by
  # concatenating profile fragments (modules/mcp.nix), which only works safely
  # because every profile above is guaranteed to have disjoint server names
  # (enforced by an eval-time assertion in modules/mcp.nix).
  toCodexFragment =
    profile:
    lib.concatStrings (
      lib.mapAttrsToList (
        name: s:
        if s.kind == "plain" then
          ''
            [mcp_servers.${name}]
            command = "${s.command}"
            args = ${builtins.toJSON s.args}
            ${lib.optionalString (s ? env) "[mcp_servers.${name}.env]\n"
            + lib.concatStrings (lib.mapAttrsToList (k: v: "${k} = \"${v}\"\n") (s.env or { }))}
          ''
        else if s.kind == "auth-http" then
          ''
            [mcp_servers.${name}]
            url = "${s.url}"

            [mcp_servers.${name}.env_http_headers]
            ${s.headerName} = "${s.envVar}"
          ''
        else if s.kind == "oauth-http" then
          ''
            [mcp_servers.${name}]
            url = "${s.url}"
          ''
        else
          ''
            # auth-stdio -- env_vars forwards these names from codex's environment.
            [mcp_servers.${name}]
            command = "${s.command}"
            args = ${builtins.toJSON s.args}
            env_vars = ${builtins.toJSON [ s.envVar ]}
          ''
      ) profile.servers
    );
}
