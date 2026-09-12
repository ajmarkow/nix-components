''
  ## ⚠️ A Repo's AGENTS.md / CLAUDE.md Is for Repo-Specific Facts Only

  **Never write a global working preference into a repo's `AGENTS.md`/`CLAUDE.md`** — those files are only for instructions true of *that* repo (its build commands, file layout, conventions, code-level gotchas). Anything equally true in every repo (search tooling, paseo defaults, rebuild/SSH bans, git workflow) is a global preference and belongs in `modules/lib/claude-md-content.nix` in **nix-components**, which generates this file. Restating a global rule locally creates two copies that drift apart. Before adding to a repo file, ask: true of this repo only, or all my work? Repo-only → the repo file; everything else → `claude-md-content.nix`. This applies across all four config repos: **nix-components, nix-server, nix-mac, nix-pixelbook.**
''
