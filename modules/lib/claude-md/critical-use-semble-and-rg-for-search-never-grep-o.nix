''
  ## ⚠️ CRITICAL: Use `semble` and `rg` for Search — Never `grep` or `find`

  **Do NOT run `grep`, `find`, or `ls` as Bash commands to search for code, files, or symbols.** These are explicitly banned for search tasks. This applies even when using the Bash tool — `rtk grep ...` and `rtk find ...` are both forbidden for search.

  **Use these instead — in priority order:**
  1. `semble search` — semantic search across the codebase (always try this first)
  2. `rtk rg` — exhaustive literal/regex match via ripgrep (exact-string confirmation)
  3. Built-in Grep/Glob tools — last resort only, when semble and rg are both unavailable

  **The wrong way (never do this):**
  ```bash
  rtk grep -r "foo" .          # ❌ banned
  rtk find . -name "*.ts"      # ❌ banned
  ```

  **The right way:**
  ```bash
  rtk semble search "authentication flow" ./my-project          # semantic search
  rtk semble search "save model to disk" ./my-project --top-k 10
  rtk rg "functionName" src/                                     # exact/regex match
  ```

  Use `--content docs`, `--content config`, or `--content all` to search beyond code:

  ```bash
  rtk semble search "deployment guide" ./my-project --content docs
  rtk semble search "database host port" ./my-project --content config
  ```

  Use `semble find-related` to discover code similar to a known location:

  ```bash
  rtk semble find-related src/auth.py 42 ./my-project
  ```

  The index builds and caches automatically; `path` defaults to `.`. If `semble` is not on `$PATH`, use `uvx --from "semble[mcp]" semble` in its place.
''
