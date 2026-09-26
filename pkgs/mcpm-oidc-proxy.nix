{
  pkgs,
  lib ? pkgs.lib,
  uv2nix,
  pyproject-nix,
  pyproject-build-systems,
}:

# Sidecar that fronts the existing mcpm aggregate (pkgs/mcpm.nix) with real
# OAuth, for clients that cannot reach the tailnet-only mcpm endpoint -- e.g.
# claude.ai's Connectors feature, which connects from Anthropic's cloud, not
# the user's tailnet (see nix-server/plans/mcpm-claude-connector-oidc.md for
# the full design). mcpm itself has no usable OAuth/OIDC hook on the
# `profile run --http` path (only a static-bearer-token hook wired to the
# unrelated `mcpm share` command), so this wraps the same backend externally
# instead of modifying mcpm.
#
# Reuses mcpm's own vendored fastmcp via its pythonEnv passthru rather than
# building a second Python environment. overlays.nix's auto-discovery gives
# every pkgs/*.nix file the same fixed extraArgs (uv2nix, pyproject-nix,
# pyproject-build-systems) -- it does not wire one custom package's output in
# as another's callPackage argument -- so importing ./mcpm.nix directly here
# is the correct way to share its build.
let
  mcpm = import ./mcpm.nix {
    inherit
      pkgs
      lib
      uv2nix
      pyproject-nix
      pyproject-build-systems
      ;
  };
in
pkgs.runCommand "mcpm-oidc-proxy"
  {
    meta.mainProgram = "mcpm-oidc-proxy";
  }
  ''
    mkdir -p $out/bin
    cat > $out/bin/mcpm-oidc-proxy <<EOF
    #!${mcpm.pythonEnv}/bin/python3
    # authlib.deprecate installs its own "always" filter for
    # AuthlibDeprecationWarning as a side effect of import, which outranks any
    # PYTHONWARNINGS-based ignore filter set before this import runs -- same
    # ordering trick pkgs/mcpm.nix uses for the same warning.
    import warnings
    import authlib.deprecate
    warnings.filterwarnings("ignore", category=authlib.deprecate.AuthlibDeprecationWarning)
    import authlib.jose

    import os

    from fastmcp import FastMCP
    from fastmcp.server.auth.oidc_proxy import OIDCProxy

    # OIDCProxy fetches the OIDC discovery document synchronously at
    # construction time -- this process will crash at startup (not just
    # misbehave) if Authelia's OIDC endpoint isn't already live. That's
    # intentional: systemd's Restart=on-failure self-heals once it is.
    auth = OIDCProxy(
        config_url=os.environ["OIDC_CONFIG_URL"],
        client_id=os.environ["OIDC_CLIENT_ID"],
        client_secret=os.environ["OIDC_CLIENT_SECRET"],
        base_url=os.environ["OIDC_BASE_URL"],
        jwt_signing_key=os.environ["OIDC_JWT_SIGNING_KEY"],
        # Passing this list REPLACES OIDCProxy's own localhost-only default
        # rather than extending it, so both claude.ai's fixed connector
        # callback (current + a possible future domain, per Anthropic's own
        # docs) and local loopback flows (Claude Code, manual testing) must
        # be listed explicitly.
        allowed_client_redirect_uris=[
            "https://claude.ai/api/mcp/auth_callback",
            "https://claude.com/api/mcp/auth_callback",
            "http://localhost:*",
            "http://127.0.0.1:*",
        ],
    )

    proxy = FastMCP.as_proxy(
        os.environ.get("MCPM_BACKEND_URL", "http://127.0.0.1:6276/mcp"),
        auth=auth,
        name="mcpm-public",
    )

    # 0.0.0.0, not loopback: Traefik reaches host systemd services through
    # the pasta NAT address (169.254.1.2) from inside the containers user's
    # rootless netns, which cannot reach a loopback-bound socket -- see
    # nix-server hosts/nixos-host/default.nix's host-route comments (paseo's
    # port 6767 uses the same pattern). Safety comes from
    # networking.firewall's default-deny, not from binding loopback: this
    # port must never be added to any interface's allowedTCPPorts.
    proxy.run(
        transport="http",
        host="0.0.0.0",
        port=int(os.environ.get("MCPM_OIDC_PROXY_PORT", "6277")),
    )
    EOF
    chmod +x $out/bin/mcpm-oidc-proxy
  ''
