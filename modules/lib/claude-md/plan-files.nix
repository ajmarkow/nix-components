''
  ## Plan Files

  - **Write plans to a `plans/` folder in the repo they relate to, not the global `~/.claude/plans` directory.** Create the folder if it doesn't exist. This keeps plan history alongside the code it describes.
  - Any plan that introduces or changes a secret must include a "Secrets" list: each secret name, plus whether it is Required or Optional. Keep it a simple list — no extra detail unless the secret's purpose is non-obvious.
''
