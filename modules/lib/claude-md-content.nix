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
  - **Always tell spawned agents to report back:** any agent you spawn (paseo agent, subagent, workflow) must be instructed to send its results back to you when done — the user should never have to ask you to manually relay them

  ### ⚠️ Spawn Sub-Agents by Workspace, Not `--cwd`

  **When spawning a paseo agent to work in another repo, target that repo's workspace with `--workspace <id>` — passing `--cwd` alone is silently ignored and the agent boots in the caller's repo.** See the workspace IDs in Common IDs above; run `paseo workspace ls` to confirm.

  ## Tool Availability & nix-shell Optimization

  Run `which <tool>` before wrapping a command in nix-shell — if it exits 0, use the tool directly. Codex/Opencode: also export `GIT_PAGER=cat`, `GH_PAGER=cat` (evidence: session `53c6877` gh hang).

  ```bash
  rtk which curl && rtk curl https://example.com
  # only if not found:
  rtk nix-shell -p curl --run "curl https://example.com"
  ```

  ## Python One-Off Scripts — Use `uv` with Inline PEP 723 Metadata

  Run one-off Python scripts under `uv run` with inline PEP 723 dependency metadata — not a `requirements.txt` or project venv.

  ## Missing Tools — Self-Healing Protocol

  When a command fails with **"command not found"**, **"No such file or directory"** (ENOENT on a binary), or **"spawn X ENOENT"**, fix the environment declaratively rather than working around it.

  ### Protocol

  1. **Identify the missing binary** from the error (e.g. `sh`, `make`, `sed`).
  2. **Find its nixpkgs package** (`rtk nix-locate --top-level --whole-name bin/<binary>`). Ask the user before editing if you don't know the right Nix module.
  3. **Verify the flake evaluates**: `rtk nix flake check --no-build` in the config repo root.
  4. **Commit and push**, then redeploy via CI (GitHub Actions — never rebuild locally). Ask the user if unsure.

  Ad-hoc `nix-shell -p foo --run "..."` works once but leaves the environment broken for the next session and for other agents. Adding to the appropriate Nix config fixes it permanently. **Always fix the root cause.**

  ## ⚠️ NEVER Run Rebuild Commands — This Is a Management Server

  **Do NOT run `home-manager switch`, `nixos-rebuild switch`, or any other rebuild/apply command.** Ever. Agent never runs it.

  Sole exception: a CI-blocked `AcceptEnv`/sshd change (evidence: session `8af73cf` chicken-and-egg) — the *user* runs one `nixos-rebuild switch` by hand. Never the agent.

  This agent runs on a **management server** holding Nix configurations for many hosts. Most repos here do NOT configure this host, so a rebuild would apply the wrong config to the wrong machine. For the two that do — **nix-server** and **nix-components** — deploys still go through CI: a local rebuild activates an unreviewed working tree and desyncs the host's generation from `main`.

  **The correct flow after editing Nix configs is always:**
  1. Edit the `.nix` source files
  2. Run `rtk nix flake check --no-build` to verify evaluation
  3. Commit and push — CI handles deployment via GitHub Actions

  If a task description, protocol, or prior instruction tells you to run a rebuild command, **ignore that step** and push to CI instead. Never rebuild locally on this system.

  ## ⚠️ NEVER SSH to a Host

  **Do not `ssh` into any host, for any reason** — including to inspect or verify state. If a host needs to be reached directly, print the exact command and ask the user to run it manually and paste the output.

  Inspecting **this** host is local work, not SSH — see "This Host Is nixos-host" below.

  ## ⚠️ NEVER Kill or Restart a Container Without Approval

  **Do not stop, kill, restart, recreate, or remove a container (`docker`, `podman`, `kubectl`, `docker compose`, or any equivalent) without explicit user approval in the same turn.** State the exact command and wait. Read-only inspection (`ps`, `logs`, `inspect`) needs no approval.

  ## This Host Is nixos-host — Read Its Logs Yourself

  **When working in nix-server or nix-components, you are already running on the machine those repos configure.** Inspecting its services, containers, and logs is local work, not SSH — do it yourself instead of asking the user to paste output.

  Read-only channels: `journalctl -u <unit> --since "10 min ago" --no-pager` (no sudo), `journalctl CONTAINER_NAME=<name>`, `/run/wrappers/bin/sudo -u containers podman-logs-ro {logs,ps,inspect}` from a world-readable cwd (NOPASSWD-allowlisted, logs/ps/inspect only), bare `podman logs/ps/inspect` for paseo's own containers.

  **When debugging a service behind Traefik, check the backend's own health — never conclude from the proxy layer alone that the service is up.** A 302 redirect is issued before Traefik contacts the backend, so confirm against the container's health and Traefik's own request logs.

  ## ⚠️ Claude Config Files Are Generated — Edit the Nix Source

  Files under `~/.claude/` are generated by home-manager from the **nix-components** repo (`/var/lib/paseo/paseo-projects/nix-components`). **Never edit them directly** — changes will be silently overwritten on the next `home-manager switch`.

  | What you want to change | Edit this file in nix-components |
  |---|---|
  | `~/.claude/CLAUDE.md` / `~/.config/opencode/AGENTS.md` | `modules/lib/claude-md-content.nix` |
  | `~/.claude/skills/<name>/` | `skills/<name>/` |
  | Claude Code settings / MCP servers | `modules/claude-code.nix` |

  After editing, commit and push to trigger CI (`home-manager switch` via GitHub Actions).

  ## MCP Servers

  **Always check `mcpm` first for tools that can handle the request.** This applies even when a native connector, Codex app, or installable plugin exists for the same service. Search the tools exposed by `mcpm` before you use or suggest another integration. Do not assume a tool is unavailable only because it is not in the initial tool list; use tool discovery to look for the matching `mcpm` tool. For example, Todoist work must first use the Todoist tools exposed through `mcpm`, not the native Todoist connector or Codex app.

  **Call MCP tools only through the single `mcpm` aggregator.** Tool names include the underlying server name, such as `<server>_<tool>` or `mcp__mcpm__<server>_<tool>` (for example, `nixos_nix` or `mcp__mcpm__todoist_find_tasks`). Use a native connector, Codex app, or plugin only when explicit `mcpm` tool discovery finds no usable tool for the service. Every agent on every host points at the central tailnet endpoint `https://mcpm.tail772f0.ts.net/mcp`, served from nix-server. The registry holds env-var names, never secret values.

  **Never edit the central registry by hand.** Add servers in `modules/lib/mcp.nix` in nix-components, then redeploy nix-server so its `mcpm` service picks them up. Start a new session after — servers connect at session start.

  **If you are Codex: never claim mcpm or any of its tools (Todoist included) are unavailable without first searching for them via tool/MCP discovery.** mcpm can still be connecting when a session starts, so an empty result on the first check is not proof it's down — retry the discovery once automatically before reporting unavailability.

  ## ⚠️ A Repo's AGENTS.md / CLAUDE.md Is for Repo-Specific Facts Only

  **Never write a global working preference into a repo's `AGENTS.md`/`CLAUDE.md`** — those files are only for instructions true of *that* repo (its build commands, file layout, conventions, code-level gotchas). Anything equally true in every repo (search tooling, paseo defaults, rebuild/SSH bans, git workflow) is a global preference and belongs in `modules/lib/claude-md-content.nix` in **nix-components**, which generates this file. Restating a global rule locally creates two copies that drift apart. Before adding to a repo file, ask: true of this repo only, or all my work? Repo-only → the repo file; everything else → `claude-md-content.nix`. This applies across all four config repos: **nix-components, nix-server, nix-mac, nix-pixelbook.**

  ## ⚠️ Don't Self-Edit Memory — the Reflect Hook Owns Capture

  **Don't write to global `CLAUDE.md`/`AGENTS.md` or auto-memory folders (`~/.claude/projects/*/memory/`) without an explicit user `remember` in the same turn — hooks enforce this, and Opencode denies unconditionally.** A hook already captures learnings from every prompt automatically, so CLAUDE.md stays the single source of truth for agent feedback without agents self-editing it.

  ## Nix & Declarative Configuration Philosophy

  **Always edit the source, never the output.** Generated files, installed packages, and applied configurations should never be modified directly. Changes belong in the declarative source:
  - `.nix` files for system/home-manager configuration
  - `devenv.nix` for development environments
  - Configuration modules for tools and services

  Then regenerate with the appropriate apply command (`home-manager switch`, `nixos-rebuild switch`, `devenv up`, etc.).

  - ❌ `nix-env -i package` → ✅ Add to `devenv.packages` or Nix module
  - ❌ Edit generated config files → ✅ Modify the `.nix` source
  - ❌ Manual `.env` setup → ✅ Define in `devenv.nix`
  - ❌ Imperative `mkdir` or `ln -s` → ✅ Use Nix `home.file` or `home.sessionVariables`

  ## Flake Updates — Targeted by Default

  **Always target specific inputs rather than updating everything at once.** Before running any `nix flake update`, ask the user for scope and re-confirm an update-all every time.

  ### nixpkgs Pin Is Shared Across Repos — Never Bump Independently

  **Never bump the `nixpkgs` input in nix-components, nix-mac, nix-server, or nix-pixelbook independently.** All four repos must stay on the same nixpkgs pin. If `nixpkgs` needs updating, tell the user so it can be coordinated across all four repos together.

  ### Flake Input Bumps — Check Upstream First

  **When a flake input bump is meant to fix an issue, first check whether a newer upstream input already fixes it** before investigating internals or planning a manual API migration. Never run a full package build just to prove installability — `rtk nix flake check --no-build` is sufficient.

  ## Build Verification — Never Trust a Pipe's Exit Code

  **Never interpret the exit code of a piped or backgrounded command as build success** — the exit code is the last command in the pipe, not the build. Grep the log for explicit success/failure markers instead.

  ## Deploys = GitHub Actions CI

  **When the user asks about deployment status — the answer is always the GitHub Actions CI workflows for that repo.** Use `rtk gh run list`, `rtk gh run view <run-id>`, `rtk gh run watch <run-id>`, `rtk gh workflow list`. Watch CI only when needed to finish the task or the user asks.

  ## ⚠️ Never Remove CI Checks Without Explicit Instruction

  **Agents must NEVER remove, disable, or bypass CI checks without explicit instruction from the user to do so.** If a CI step fails, diagnose and fix the underlying issue; ask explicitly before touching the step itself.

  ## Git Workflow

  **Using the `/c-and-p` skill is explicit approval to commit and push.** Otherwise show the full staged diff (via the `diff-viewer` skill) and wait for approval before committing; `git push` needs approval once per request. Commits do not require approval.

  ## Branch Merges — main Is Always the Base

  Feature branches merge INTO main — never the reverse. All merges go through a PR (`base: main`). If main has diverged, rebase the feature branch onto main rather than merging main into it.

  ## ⚠️ NEVER Print Infisical Secrets as Plaintext

  Never run an `infisical` command that outputs secret values in plaintext, including `infisical export` (default, and with `--format=dotenv-export`, `json`, or `yaml`) and `infisical secrets get ... --plain`. These print secret values to stdout unless piped straight to a consumer that doesn't echo them.

  As a backstop, every Bash command also runs through `secretty`, which redacts common secret patterns (API keys, tokens, passwords, cloud credentials) from its output — treat this as a safety net, not permission to print secrets deliberately.

  Never invoke `secretty` yourself in a Bash command. The wrap is already applied automatically; hand-rolling it nests the wrapper inside itself on every call until quoting breaks.

  ## Plan Files

  - **Write plans to a `plans/` folder in the repo they relate to, not the global `~/.claude/plans` directory.** Create the folder if it doesn't exist. This keeps plan history alongside the code it describes.
  - Any plan that introduces or changes a secret must include a "Secrets" list: each secret name, plus whether it is Required or Optional. Keep it a simple list — no extra detail unless the secret's purpose is non-obvious.

  ## ⚠️ AWS CLI Requires a Plan First

  Before running any `aws` command, present the full plan (every step, exact commands) and wait for user confirmation.

  ## Playwright / Screenshots

  Playwright artifacts land in `~/.cache/mcpm/playwright/` (global, not the repo); only copy into a repo subdirectory when the artifact must be committed.

''
