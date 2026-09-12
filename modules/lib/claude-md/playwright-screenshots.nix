''
  ## Playwright / Screenshots

  Playwright screenshots and other artifacts land in `~/.cache/mcpm/playwright/` on nix-server. The shared `mcpm` service resolves relative output names in this global directory, not in the caller's repository. Copy an artifact into a repository only when it must be committed, and put it in a subdirectory, never the repository root.

''
