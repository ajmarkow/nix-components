''
  ## Inter-Agent Messaging

  When the user asks you to message, notify, or send something to another agent or repo, **use Paseo** — not files, git, or any other mechanism.

  **Always use the Paseo MCP tools when they are available.** Use the `paseo` CLI only when the Paseo MCP interface is completely unavailable. Do not choose the CLI merely because it is familiar or convenient.

  **CLI fallback:** Run bare `paseo`; it does not need the `rtk` prefix. Configured remote clients already supply their connection settings, and local daemon operations need no `PASEO_HOST`.

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

  When MCP is unavailable, find the target agent and send with the CLI:
  ```bash
  paseo ls -a -g                         # list all agents across all directories
  paseo send <id> "message or task"      # id can be shortened if unambiguous
  ```

  If no relevant agent is running, spawn a new one:
  ```bash
  paseo run "task" --detach --name <name> --model sonnet --mode auto
  ```

  Other commands:
  ```bash
  paseo attach <id>   # stream output live
  paseo wait <id>     # block until agent finishes
  paseo stop <id>     # terminate
  ```

  ### ⚠️ Spawn Sub-Agents by Workspace, Not `--cwd`

  **When spawning a paseo agent to work in another repo, target that repo's workspace with `--workspace <id>` — passing `--cwd` alone is silently ignored and the agent boots in the caller's repo.**

  Why: agent-scoped `paseo run` defaults to the *caller's* workspace. `--cwd` sets a process directory but does not switch workspaces, so the child ends up back in the caller's repo.

  ```bash
  # 1. Find the workspace id (match on the PROJECT / CWD columns)
  paseo workspace ls

  # 2. Spawn into that workspace
  paseo run "remove pylsp from neovim config" \
    --workspace wks_6d815c666fe4cf4b \
    --detach --name remove-pylsp --provider claude/claude-sonnet-4-6 --mode auto

  # No workspace exists yet for the repo? Create one:
  #   paseo run "..." --new-workspace local --cwd /var/lib/paseo/paseo-projects/<repo> --mode auto ...
  ```

  Verify: `paseo run` prints `Using workspace <id>` and the CWD column shows the target repo. Pass the ID exactly as `paseo workspace ls` prints it — it may be a `wks_` id or a path.
''
