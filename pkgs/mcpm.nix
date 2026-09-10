{
  pkgs,
  lib ? pkgs.lib,
  uv2nix,
  pyproject-nix,
  pyproject-build-systems,
}:

# Built from mcpm's own PyPI metadata via uv2nix rather than from the upstream
# mcpm.sh flake. That flake hand-maintains propagatedBuildInputs and omits
# several declared dependencies (tomli, tomli-w, rich-click, inquirerpy,
# rich-gradient, jsonschema, fastmcp), so `mcpm` died on ModuleNotFoundError at
# runtime. uv resolves the full set from pyproject.toml, so there is no list to
# keep in sync here.
let
  workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./mcpm-workspace; };

  overlay = workspace.mkPyprojectOverlay {
    sourcePreference = "wheel";
  };

  python = pkgs.python3;

  pythonSet =
    (pkgs.callPackage pyproject-nix.build.packages {
      inherit python;
    }).overrideScope
      (
        lib.composeManyExtensions [
          pyproject-build-systems.overlays.wheel
          overlay
          (_: prev: {
            mcpm = prev.mcpm.overrideAttrs (old: {
              postInstall = (old.postInstall or "") + ''
                substituteInPlace "$out/${python.sitePackages}/mcpm/fastmcp_integration/proxy.py" \
                  --replace-fail 'import logging' $'import logging\nimport os' \
                  --replace-fail 'env_config.update(server.env)' \
                    'env_config.update(server.get_filtered_env_vars(os.environ))'

                # find_available_port's probe socket never sets SO_REUSEADDR, so a
                # fresh bind() to the just-vacated port fails while the previous
                # instance's closed HTTP/SSE connections still sit in TIME_WAIT --
                # even though the real server socket (uvicorn) already sets
                # SO_REUSEADDR and would bind that same port fine. The probe reads
                # that as "busy" and silently walks up to the next port, so every
                # restart of a long-lived profile can drift off its configured
                # port with no error. `mcpm profile run` is what modules/mcp.nix's
                # systemd service invokes, so that's the copy that matters here.
                substituteInPlace "$out/${python.sitePackages}/mcpm/commands/profile/run.py" \
                  --replace-fail \
                    's.bind(("127.0.0.1", port_to_try))' \
                    's.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind(("127.0.0.1", port_to_try))'
              '';
            });
          })
        ]
      );

  mcpm-env = pythonSet.mkVirtualEnv "mcpm-env" workspace.deps.default;
in
# mkVirtualEnv exposes all venv binaries (python3, pip, etc.) which conflict
# with system packages. Wrap to expose only the mcpm binary.
pkgs.runCommand "mcpm"
  {
    meta.mainProgram = "mcpm";
    passthru.pythonEnv = mcpm-env;
  }
  ''
      mkdir -p $out/bin
      cat > $out/bin/mcpm <<EOF
    #!${mcpm-env}/bin/python3
    # authlib.deprecate installs its own "always" filter for
    # AuthlibDeprecationWarning as a side effect of import, which outranks any
    # PYTHONWARNINGS-based ignore filter (or one set before this import runs).
    # Importing it first, then adding our ignore filter, then triggering the
    # actual warning via the authlib.jose import puts our filter in front.
    import warnings
    import authlib.deprecate
    warnings.filterwarnings("ignore", category=authlib.deprecate.AuthlibDeprecationWarning)
    import authlib.jose

    import sys
    from mcpm.cli import main

    if __name__ == "__main__":
        sys.exit(main())
    EOF
      chmod +x $out/bin/mcpm
  ''
