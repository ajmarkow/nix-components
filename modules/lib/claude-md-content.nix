# Shared prose for both Claude Code's CLAUDE.md and opencode's AGENTS.md.
#
# This is a plain string, not a home-manager module — do NOT move it into
# ../modules/ directly; home-modules.nix auto-imports every top-level .nix
# file there as a home module, which would break on a bare string. Reading
# it back out of `config.home.file.".claude/CLAUDE.md".text` from a second
# module (as opencode.nix originally did) causes infinite recursion, because
# home-manager's `programs.opencode.context` folds into `xdg.configFile`,
# which folds back into `home.file` — so `home.file` can't be evaluated
# while it's still evaluating itself. Importing this file directly sidesteps
# that: it's just a string, independent of `config`.
''
  # Bash Tool Guidelines — MANDATORY

  ## ⚠️ CRITICAL: Use `rtk` only for its supported subcommands — everything else runs directly

  `rtk` is a proxy with a **fixed, closed set of subcommands** (run `rtk --help` for the current list). Prefixing a command it doesn't recognize (e.g. `rtk nix ...`, `rtk mkdir ...`) fails outright with "No such file or directory" — there is no generic passthrough.

  A PreToolUse hook already rewrites every Bash command through `rtk`'s equivalent automatically, whether or not you type the prefix — so don't add `rtk` yourself just to trigger it. The `rtk`-prefixed examples in this file (below and elsewhere) are documentation convention, not a required action. Same for `secretty`: the redaction wrap is applied automatically, so never type it into a command yourself.

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

  See `semble --help` for `--content` scoping and `find-related`. The index builds and caches automatically; `path` defaults to `.`.

  ## Context & Session Discipline

  ### Two-Strike Rule

  After **two failed attempts on the same issue**, stop. **Do not try a third fix.** Invoke the `debug-with-llms` skill and follow it. It replaces more attempts.

  ### Cap Shell Output

  Cap shell command output by default. Use focused filters (`--no-pager`, `head`, `grep`, line-range flags) and paste only the relevant failing excerpt back into context — never the full raw output.

  ### File Reading Discipline

  Before rereading a file, summarize what you already know about it. Prefer targeted symbol searches (`rg`, LSP go-to-definition) or narrow line ranges (`offset`/`limit`) over whole-file reads.

  ## Fetching Web Content

  Prefer `rtk defuddle parse <url> --md` over `WebFetch` for standard web pages. Fall back to `WebFetch` for raw JSON APIs or authenticated services.

  ## Response Style — ASD-STE100

  Be a supportive colleague: plain talk, questions decisions that hurt goals.

  Write responses to the user in ASD-STE100 (Simplified Technical English) style: short sentences, active voice, plain vocabulary. Keep the tone casual and conversational — STE is about clarity, not formality.

  This applies to written documentation and CLAUDE.md content too: short declarative sentences, no formal or hedging register, no framing the user did not ask for.

  **Do not make jokes unless they are funny.**

  **Code comments state only why the code exists or what the non-obvious issue is — never how the change was arrived at.** Keep them to the minimum a future reader needs; no narration of the debugging path.

  **If the user asks for unrendered markdown, show it in a code block — do not render it.**

  **If the user asks for no markdown or plain text, use plain text only. Use no markdown formatting.**

  Do not add docstrings unless the user explicitly asks.

  ## Decision Points — Use AskUserQuestion

  Default to `AskUserQuestion` (not prose) for major/medium decisions: tradeoffs between approaches, risky/hard-to-reverse actions, or requirement ambiguity that changes the outcome. Skip it for calls you can resolve yourself (style, reading the code) or quick clarifications that don't need structured options. Batch related questions into one call.

  Rule of thumb: if you'd write "Would you like X or Y?" in prose, ask it as `AskUserQuestion` instead.

  ## Agentic Task Board — Mandatory

  Use the Todoist **Agentic** project as the source of truth for agent work.

  **Track substantial work only** — features, bugs, and multi-step changes. Skip the board for simple flake input bumps and operational or informational questions (status checks, log lookups, "is X deployed", explaining existing behavior).

  Before you begin work:

  1. Search the Agentic project for a task that matches the request.
  2. If no matching task exists, create one in **Queue**. Give it a clear title and a description that includes the goal, context, constraints, and expected result.
  3. Move the task to **Active** when work begins.

  Keep the task current throughout the work:

  - **Queue** — The task is defined and ready, but work has not started.
  - **Active** — An agent is investigating, implementing, or documenting the task.
  - **Needs You** — Progress requires a user decision, approval, credential, or other input. Add a comment that states exactly what is needed.
  - **Testing** — Implementation is complete and is being checked against the task requirements.
  - **Done** — Work is complete and verified. Add a final update that summarizes the result and links to relevant changes or outputs.

  Update the task when its status, scope, blocker, or result changes. Do not begin untracked work. Do not mark a task **Done** until the requested result is complete and verified.

  If Todoist is unavailable, stop before beginning the task and tell the user that board tracking is blocked.

  ## Common IDs — Shorthand

  Use these stable values directly. Skip the lookup calls. Re-list on failure — IDs drift.

  Todoist Agentic project `6hHv4pRr5cJG77Xg`. Inbox `6Crf9RMq9wH5xF69`.

  | Section | ID |
  |---|---|
  | Queue | `6hQqHqJgqmR23rr8` |
  | Active | `6hQqHqJhpvq74CCg` |
  | Needs You | `6hQqHqHxMfRwRMhg` |
  | Testing | `6hV2xHG7JG3C8cHg` |
  | Done | `6hQqHqHMhR2V4c6g` |
  | Awaiting Usage | `6hVMv8W2PXMCff4g` |

  Paseo PRIMARY workspaces. Spawn with `--workspace`, never `--cwd` alone.

  | Workspace | Cwd | Title |
  |---|---|---|
  | `wks_582cc0bd6b48e4f3` | `/var/lib/paseo/projects/nix-server` | PRIMARY_NIX-SERVER |
  | `wks_5304173c1a50b772` | `/var/lib/paseo/projects/nix-components` | PRIMARY_NIX-COMPONENTS |
  | `wks_c81b121f3da04122` | `/var/lib/paseo/projects/nix-pixelbook` | PRIMARY_NIX-PIXELBOOK |
  | `wks_c2810533f5d2e6d1` | `/var/lib/paseo/projects/nix-mac` | PRIMARY_NIX-MAC |
  | `wks_430ad05f6e16257b` | `/var/lib/paseo/projects` | PRIMARY |

  | Fact | Value |
  |---|---|
  | Owner | `ajmarkow` (nix-server, nix-components, nix-mac, nix-pixelbook) |
  | Canonical path | `/var/lib/paseo/projects/<repo>` (`paseo-projects/` is a symlink) |
  | Obsidian vault | `agentic` (renamed from `main` — never use `main`) |
  | This host | `nixos-host` = `ajm-nix-server.tail772f0.ts.net` |
  | Stable tailnet names | `homepage`, `storage`, `plex`, `mcpm` |
  | Darwin host | `AJ-MARKOW-WORK-MACBOOK-PRO` |

  ## Inter-Agent Messaging

  When the user asks you to message, notify, or send something to another agent or repo, **use Paseo** — not files, git, or any other mechanism.

  **Always use the Paseo MCP tools when they are available.** Use the `paseo` CLI (`paseo ls -a -g`, `paseo send <id>`, `paseo run ... --workspace <id>`) only when the Paseo MCP interface is completely unavailable.

  **CLI fallback:** Run bare `paseo`; it does not need the `rtk` prefix.

  **Host diagnostics:** A sandbox or container can see host files without sharing the host PID namespace or loopback, so rerun read-only diagnostics with approved host access before reporting that a local daemon is stopped or unreachable, or recommending a restart.

  ### ⚠️ Never Restart or Stop the Paseo Daemon

  **Do not restart or stop the paseo daemon, for any reason — including while it is running.** This is a user-only action. Tell the user the daemon needs restarting or stopping and let them run it.

  ### ⚠️ Never Put the Paseo Password on a Command Line

  **Never put the password in a `--host` URI, print `PASEO_PASSWORD`, or write it to a file — the env vars are the only sanctioned channel.**

  - If paseo reports unauthorized or unreachable, run `infisical login`, or confirm the token file exists with `test -s ~/.config/infisical-token` — never print its contents. Retry in a fresh shell.
  - If a configured remote host is down, report that problem. Do not change the host environment to target another daemon. `paseo status` is local-only, so it succeeds regardless and does not prove the remote is reachable.
  - Headless contexts without shell init (cron, launchd): use `paseo-headless <args>` — it sets `PASEO_HOST`/`PASEO_PASSWORD` itself. Never fetch the password by hand.

  **Agent Selection Strategy:**
  - **Use existing agent** if it is directly relevant to the task/message being sent (same repo, same module, immediate follow-up, or closely related work)
  - **Spawn new agent** otherwise (different context, different area, unrelated work)
  - **Default model:** Use Sonnet when spawning new agents
  - **Use automatic permission review for Paseo subagents:** Select `auto` mode for Claude, `auto-review` mode for Codex, and `auto_accept = true` for OpenCode.
  - **Always tell spawned agents to report back:** any agent you spawn (paseo agent, subagent, workflow) must be instructed to send its result
''
