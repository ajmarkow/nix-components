{ lib, inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      pkgsDir = ./pkgs;
      extraArgs = {
        inherit (inputs) uv2nix pyproject-nix pyproject-build-systems;
      };
      customPackages =
        lib.mapAttrs'
          (
            name: _:
            lib.nameValuePair (lib.removeSuffix ".nix" name) (pkgs.callPackage (pkgsDir + "/${name}") extraArgs)
          )
          (
            lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".nix" name) (
              builtins.readDir pkgsDir
            )
          );
    in
    {
      formatter = pkgs.nixfmt-rfc-style;

      checks = {
        infisical-secrets =
          let
            apps = (import ./lib/infisical-secrets.nix) {
              inherit pkgs;
              projectId = "00000000-0000-0000-0000-000000000000";
              hostFolder = "/test-host";
              secretsDir = "/etc/test-host/secrets";
              manifest = [
                {
                  file = "example.env";
                  keys = [
                    "FIRST_SECRET"
                    "SECOND_SECRET"
                  ];
                  template = ''
                    FIRST_SECRET=$FIRST_SECRET
                    SECOND_SECRET=$SECOND_SECRET
                  '';
                }
              ];
              rebuildCommand = "true";
            };
          in
          pkgs.runCommand "infisical-secrets-tests" { } ''
            ${pkgs.shellcheck}/bin/shellcheck ${apps.secrets.program}
            ${pkgs.shellcheck}/bin/shellcheck ${apps.rebuild.program}
            ${apps.secrets.program} --help > /dev/null

            login_home="$TMPDIR/login-home"
            mkdir -p "$login_home"
            printf 'test-client-id\ntest-client-secret\n' | \
              HOME="$login_home" ${apps.infisical-login.program} > "$TMPDIR/login-output"
            test "$(stat -c '%a' "$login_home/.config/infisical")" = 700
            test "$(stat -c '%a' "$login_home/.config/infisical/universal-auth-client-id")" = 600
            test "$(stat -c '%a' "$login_home/.config/infisical/universal-auth-client-secret")" = 600
            test "$(<"$login_home/.config/infisical/universal-auth-client-id")" = test-client-id
            test "$(<"$login_home/.config/infisical/universal-auth-client-secret")" = test-client-secret
            if grep -Eq 'test-client-id|test-client-secret' "$TMPDIR/login-output"; then
              echo "credential value leaked into login output" >&2
              exit 1
            fi

            empty_home="$TMPDIR/empty-home"
            mkdir -p "$empty_home"
            if HOME="$empty_home" env \
              -u INFISICAL_TOKEN \
              -u INFISICAL_UNIVERSAL_AUTH_ACCESS_TOKEN \
              -u INFISICAL_UNIVERSAL_AUTH_CLIENT_ID \
              -u INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET \
              ${apps.secrets.program} --dry-run > "$TMPDIR/missing-output" 2>&1; then
              echo "secrets unexpectedly succeeded without credentials" >&2
              exit 1
            fi
            grep -q "No Infisical credentials found" "$TMPDIR/missing-output"
            touch "$out"
          '';

        # Scoped to exactly the files each test touches (rather than `${./.}`,
        # which copies the whole repo) so these drvPaths stay stable across
        # unrelated changes elsewhere in the tree -- load-bearing for the
        # drv-equivalence harness in tests/equivalence, which would otherwise
        # see every commit as touching these two checks.
        diff-viewer = pkgs.runCommand "diff-viewer-tests" { } ''
          cd ${
            lib.fileset.toSource {
              root = ./.;
              fileset = lib.fileset.unions [
                ./tests/test_diff_viewer_header.py
                ./scripts/diff-viewer-header.py
                ./skills/diff-viewer/frappe.css
                ./modules/diff-viewer.nix
                ./per-system.nix
              ];
            }
          }
          PYTHONDONTWRITEBYTECODE=1 ${pkgs.python3}/bin/python3 -m unittest tests/test_diff_viewer_header.py
          touch "$out"
        '';

        mcpm-environment = pkgs.runCommand "mcpm-environment-tests" { } ''
          cd ${
            lib.fileset.toSource {
              root = ./.;
              fileset = ./tests/test_mcpm_env.py;
            }
          }
          PYTHONDONTWRITEBYTECODE=1 ${customPackages.mcpm.pythonEnv}/bin/python3 -m unittest tests/test_mcpm_env.py
          touch "$out"
        '';

        mcpm-central =
          let
            result = import ./tests/mcpm-central.nix {
              inherit (pkgs) lib;
              inherit pkgs;
            };
          in
          if result.ok then
            pkgs.runCommand "mcpm-central-tests" { } ''
              touch "$out"
            ''
          else
            throw result.message;
      };

      devShells.default = pkgs.mkShell {
        packages = [
          pkgs.nil
          pkgs.nixfmt-rfc-style
          pkgs.statix
          pkgs.deadnix
        ];
      };

      packages = customPackages;
    };
}
