''
  ## Flake Updates — Targeted by Default

  **Always target specific inputs rather than updating everything at once.** Before running any `nix flake update`, ask the user for scope:

  1. **List named inputs** from `flake.lock` or `flake.nix` so the user can see what's available.
  2. **Ask**: "Which inputs would you like to update? (list specific names, or 'all' to update everything)"
  3. Update only what the user confirms.

  ```bash
  # Targeted (preferred)
  rtk nix flake update nixpkgs
  rtk nix flake update nixpkgs home-manager

  # Update all (only when user explicitly requests it)
  rtk nix flake update
  ```

  Updating all inputs at once can introduce unexpected breakage across unrelated packages. Targeted updates keep changes reviewable and rollbacks easy.

  ### ⚠️ Update-All Requires Explicit Re-Confirmation

  If the user asks to update all inputs (e.g. "update all flakes", "run nix flake update"), **do not execute immediately**. Instead:

  1. List every named input that will be updated.
  2. Explicitly warn: "This will update ALL inputs, which may introduce breaking changes."
  3. Ask: "Confirm you want to update all of the above inputs?"
  4. **Only proceed after the user says yes in that same turn.**

  A prior "update everything" instruction is not standing permission — re-confirm every time.

  ### ⚠️ Never Run `nix flake update` Outside the Current Working Directory

  **Only ever run `nix flake update` (targeted or otherwise) against the flake in your current working directory.** Never pass a path to a different repo, `cd` into another flake to update it, or target a flake elsewhere on disk.

  This agent may have several unrelated flake repos checked out on the same system. Updating a flake you're not actively working in changes `flake.lock` for a repo you have no context on, bypasses review, and can surprise whoever owns that repo. If a flake elsewhere needs updating, tell the user or hand the task to an agent whose working directory is that repo — don't reach out and update it from here.

  ### nixpkgs Pin Is Shared Across Repos — Never Bump Independently

  **Never bump the `nixpkgs` input in nix-components, nix-mac, nix-server, or nix-pixelbook independently.** All four repos must stay on the same nixpkgs pin. If `nixpkgs` needs updating, tell the user so it can be coordinated across all four repos together.

  ### Flake Input Bumps — Check Upstream First

  **When a flake input bump is meant to fix an issue, first check whether a newer upstream input already fixes it** before investigating internals or planning a manual API migration. Never run a full package build just to prove installability — `rtk nix flake check --no-build` is sufficient.
''
