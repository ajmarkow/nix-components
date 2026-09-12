''
  ## ⚠️ CRITICAL: Use `rtk` only for its supported subcommands — everything else runs directly

  `rtk` is a proxy with a **fixed, closed set of subcommands** (run `rtk --help` for the current list). Prefixing a command it doesn't recognize (e.g. `rtk nix ...`, `rtk mkdir ...`) fails outright with "No such file or directory" — there is no generic passthrough.

  A PreToolUse hook already rewrites every Bash command through `rtk`'s equivalent automatically, whether or not you type the prefix — so don't add `rtk` yourself just to trigger it. The `rtk`-prefixed examples in this file (below and elsewhere) are documentation convention, not a required action.

  **`rtk` recognizes:** `ls, tree, read, smart, git, gh, glab, aws, psql, pnpm, err, test, json, deps, env, find, diff, log, dotnet, docker, kubectl, summary, grep, init, wget, wc, gain, cc-economics, config, jest, vitest, prisma, tsc, next, lint, prettier, format, playwright, cargo, npm, npx, curl, discover, session, telemetry, learn, ruff, pytest, mypy, rake, rubocop, rspec, pip, go, gt, golangci-lint, gradlew`.

  **Never add `rtk` to anything outside that list** — including `nix`, `mkdir`, `rm`, `cp`, `cat`, `sed`, `awk`, and `paseo`; run those directly. To get rtk's tracking on an unlisted command anyway, use `rtk run "<command>"` or `rtk proxy <command>` — never guess a subcommand that isn't in the list.

  **⚠️ The rewrite cannot be avoided by typing choices, and its output is not the tool's native format.** A recognized subcommand gets rewritten either way, so if you're piping output into a parser (`diff2html`, `jq` expecting a specific shape, etc.), typing or omitting `rtk` makes no difference — `rtk git diff`, for example, is a pretty-printed summary with no `diff --git` headers. Invoke the binary by absolute path (e.g. `/run/current-system/sw/bin/git`) to bypass the rewrite and get native output.

  ```bash
  rtk git status
  rtk git push origin main
  nix flake check --no-build   # not an rtk subcommand — run directly
  mkdir -p .github/workflows   # not an rtk subcommand — run directly
  paseo ls                     # paseo is exempt
  /run/current-system/sw/bin/git diff | diff2html -i stdin ...   # piping into a parser — bypass the rewrite
  ```
''
