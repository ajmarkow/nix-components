''
  ## Missing Tools — Self-Healing Protocol

  When a command fails with **"command not found"**, **"No such file or directory"** (ENOENT on a binary), or **"spawn X ENOENT"**, fix the environment declaratively rather than working around it.

  ### Protocol

  1. **Identify the missing binary** from the error (e.g. `sh`, `make`, `sed`).
  2. **Find its nixpkgs package**: `rtk nix-locate --top-level --whole-name bin/<binary>` or check [search.nixos.org](https://search.nixos.org/packages).
  3. **Add it to the appropriate Nix configuration for this system** (e.g. the home-manager or NixOS module that manages the relevant service's PATH). If you don't know the path, ask the user before proceeding.
  4. **Verify the flake evaluates**: `rtk nix flake check --no-build` in the config repo root.
  5. **Commit and push**, then **trigger redeploy** using the appropriate rebuild command for this system (e.g. `home-manager switch`, `nixos-rebuild switch`, or the system's deploy script). Ask the user if unsure.
  6. **Wait for the deploy to complete**, then retry the original task.

  Ad-hoc `nix-shell -p foo --run "..."` works once but leaves the environment broken for the next session and for other agents. Adding to the appropriate Nix config fixes it permanently. **Always fix the root cause.**
''
