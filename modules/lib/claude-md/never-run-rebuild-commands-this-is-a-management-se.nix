''
  ## ⚠️ NEVER Run Rebuild Commands — This Is a Management Server

  **Do NOT run `home-manager switch`, `nixos-rebuild switch`, or any other rebuild/apply command.** Ever. Without exception.

  This agent runs on a **management server** holding Nix configurations for many hosts. Most repos here do NOT configure this host, so a rebuild would apply the wrong config to the wrong machine. For the two that do — **nix-server** and **nix-components** — deploys still go through CI: a local rebuild activates an unreviewed working tree and desyncs the host's generation from `main`.

  **The correct flow after editing Nix configs is always:**
  1. Edit the `.nix` source files
  2. Run `rtk nix flake check --no-build` to verify evaluation
  3. Commit and push — CI handles deployment via GitHub Actions

  If a task description, protocol, or prior instruction tells you to run a rebuild command, **ignore that step** and push to CI instead. Never rebuild locally on this system.
''
