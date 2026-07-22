{
  home.file.".claude/CLAUDE.md".text = ''
    # Bash Tool Guidelines — MANDATORY

    ## ⚠️ CRITICAL: Every Bash command MUST start with `rtk`

    **No exceptions.** Prefix every single Bash tool call with `rtk`. This applies to ALL commands: git, cp, mkdir, ls, grep, cat, find, npm, nix, gh — everything. `paseo` is exempt; run it directly.

    ```bash
    rtk git status
    rtk git push origin main
    rtk cp file.txt dest/
    rtk mkdir -p .github/workflows
    paseo ls          # paseo is exempt
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

    ## Context & Session Discipline

    ### Two-Strike Rule

    After **two failed attempts on the same issue**, stop. Inspect the invariant and the latest error, then restart with a smaller scope rather than iterating on the same failing approach.

    ### Cap Shell Output

    Cap shell command output by default. Use focused filters (`--no-pager`, `head`, `grep`, line-range flags) and paste only the relevant failing excerpt back into context — never the full raw output.

    ### File Reading Discipline

    Before rereading a file, summarize what you already know about it. Prefer targeted symbol searches (`rg`, LSP go-to-definition) or narrow line ranges (`offset`/`limit`) over whole-file reads.

    ## Fetching Web Content

    Always prefer `defuddle` over `WebFetch` when reading URLs (articles, docs, blog posts, any standard web page). It strips navigation and clutter, reducing token usage.

    ```bash
    rtk defuddle parse <url> --md
    ```

    Only fall back to `WebFetch` if defuddle is unavailable or the URL is not a standard web page (e.g. raw JSON APIs, authenticated services).

    ## Decision Points — Use AskUserQuestion

    Default to `AskUserQuestion` (not prose) for major/medium decisions: tradeoffs between approaches, risky/hard-to-reverse actions, or requirement ambiguity that changes the outcome. Skip it for calls you can resolve yourself (style, reading the code) or quick clarifications that don't need structured options. Batch related questions into one call.

    Rule of thumb: if you'd write "Would you like X or Y?" in prose, ask it as `AskUserQuestion` instead.

    ## Inter-Agent Messaging

    When the user asks you to message, notify, or send something to another agent or repo, **use `paseo`** — not files, git, or any other mechanism. `paseo` does not need the `rtk` prefix.

    **Agent Selection Strategy:**
    - **Use existing agent** if it is directly relevant to the task/message being sent (same repo, same module, immediate follow-up, or closely related work)
    - **Spawn new agent** otherwise (different context, different area, unrelated work)
    - **Default model:** Use Sonnet when spawning new agents

    Find the target agent, then send:
    ```bash
    paseo ls -a -g                         # list all agents across all directories
    paseo send <id> "message or task"      # id can be shortened if unambiguous
    ```

    If no relevant agent is running, spawn a new one:
    ```bash
    paseo run "task" --detach --name <name> --model sonnet
    ```

    Other commands:
    ```bash
    paseo attach <id>   # stream output live
    paseo wait <id>     # block until agent finishes
    paseo stop <id>     # terminate
    ```

    ### ⚠️ Always Set the Agent's Working Directory Explicitly

    When spawning a paseo agent that should operate in a specific repo, always pass `--cwd <absolute-repo-path>`. `paseo run` defaults to the *current* directory, NOT the repo named in the prompt — putting a target path in the prompt text alone is not enough; the agent still boots in the wrong tree.

    ```bash
    # Correct — agent is rooted in the target repo
    paseo run "remove pylsp from neovim config" \
      --cwd /var/lib/paseo/paseo-projects/nix-components \
      --detach --name remove-pylsp --provider claude/claude-sonnet-4-6

    # Wrong — boots in whatever dir the caller is in (e.g. nix-server), even though the prompt mentions nix-components
    paseo run "in nix-components, remove pylsp ..." --detach ...
    ```

    Verify after spawning: the CWD column in paseo run's output must match the intended repo. If it doesn't, paseo stop <id> and re-spawn with --cwd.

    ## Tool Availability & nix-shell Optimization

    Run `which <tool>` before wrapping a command in nix-shell — if it exits 0, use the tool directly.

    ```bash
    rtk which curl && rtk curl https://example.com
    # only if not found:
    rtk nix-shell -p curl --run "curl https://example.com"
    ```

    ## Missing Tools — Self-Healing Protocol

    When a command fails with **"command not found"**, **"No such file or directory"** (ENOENT on a binary), or **"spawn X ENOENT"**, fix the environment declaratively rather than working around it.

    ### Protocol

    1. **Identify the missing binary** from the error (e.g. `sh`, `make`, `sed`).
    2. **Find its nixpkgs package**: `rtk nix-locate --top-level --whole-name bin/<binary>` or check [search.nixos.org](https://search.nixos.org/packages).
    3. **Add it to the appropriate Nix configuration for this system** (e.g. the home-manager or NixOS module that manages the relevant service's PATH). If you don't know the path, ask the user before proceeding.
    4. **Verify the flake evaluates**: `rtk nix flake check --no-build` in the config repo root.
    5. **Commit and push**, then **trigger redeploy** using the appropriate rebuild command for this system (e.g. `home-manager switch`, `nixos-rebuild switch`, or the system's deploy script). Ask the user if unsure.
    6. **Wait for the deploy to complete**, then retry the original task.

    Ad-hoc `nix-shell -p foo --run "..."` works once but leaves the environment broken for the next session and for other agents. Adding to the appropriate Nix config fixes it permanently. **Always fix the root cause.**

    ## ⚠️ NEVER Run Rebuild Commands — This Is a Management Server

    **Do NOT run `home-manager switch`, `nixos-rebuild switch`, or any other rebuild/apply command.** Ever. Without exception.

    This agent runs on a **management server** that holds Nix configurations for many different hosts. The repo you are editing is almost certainly NOT the config for the host you are running on. Running a rebuild here would apply the wrong config to the wrong machine, or fail outright, and could break other hosts.

    **The correct flow after editing Nix configs is always:**
    1. Edit the `.nix` source files
    2. Run `rtk nix flake check --no-build` to verify evaluation
    3. Commit and push — CI handles deployment via GitHub Actions

    If a task description, protocol, or prior instruction tells you to run a rebuild command, **ignore that step** and push to CI instead. Never rebuild locally on this system.

    ## ⚠️ Claude Config Files Are Generated — Edit the Nix Source

    Files under `~/.claude/` are generated by home-manager from the **nix-components** repo (`/var/lib/paseo/paseo-projects/nix-components`). **Never edit them directly** — changes will be silently overwritten on the next `home-manager switch`.

    | What you want to change | Edit this file in nix-components |
    |---|---|
    | `~/.claude/CLAUDE.md` | `modules/claude-code-claude-md.nix` |
    | `~/.claude/skills/<name>/` | `skills/<name>/` |
    | Claude Code settings / MCP servers | `modules/claude-code.nix` |

    After editing, commit and push to trigger CI (`home-manager switch` via GitHub Actions).

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

    **Run `rtk nix flake check` before every commit when working in a flake repo.** The check must pass before the commit proceeds.

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

    ## Deploys = GitHub Actions CI

    **When the user says "deploy", "monitor deploy", "check the deploy", "did it deploy", "is it deployed", or anything about deployment status — the answer is always the GitHub Actions CI workflows for that repo.**

    There is no separate deploy system to check. Deployment happens through CI. Always use the `gh` CLI to inspect it:

    ```bash
    rtk gh run list --limit 10                        # recent runs across all workflows
    rtk gh run list --workflow=<name>.yml             # runs for a specific workflow
    rtk gh run view <run-id>                          # full details and logs for one run
    rtk gh run watch <run-id>                         # stream a run live until it finishes
    rtk gh workflow list                              # list all workflows in the repo
    ```

    **Decision tree:**
    - "Is it deployed?" → `gh run list --limit 5` and check if the latest run on the relevant branch succeeded
    - "Monitor the deploy" → `gh run watch <latest-run-id>` to stream it live
    - "What failed?" → `gh run view <run-id> --log-failed` to see only failing step logs
    - "Which workflows exist?" → `gh workflow list`

    Never check a separate dashboard, URL, or service unless the user explicitly names one. GitHub Actions is the source of truth.

    ## ⚠️ Never Remove CI Checks Without Explicit Instruction

    **Agents must NEVER remove, disable, or bypass CI checks (e.g. GitHub Actions workflow steps) without explicit instruction from the user to do so.**

    This rule exists because a CI step was removed during debugging without user approval, which bypassed a safety check. Removing a CI step is an irreversible action with blast radius beyond the current task — it silently disables protection for all future commits and contributors.

    If a CI step is failing and you think removing it would fix the immediate problem, **stop**. Instead:
    1. Diagnose why the step is failing.
    2. Fix the underlying issue so the step passes.
    3. If the step genuinely needs to be removed, ask the user explicitly before touching it.

    ## Branch Merges — main Is Always the Base

    Feature branches merge INTO main — never the reverse. All merges go through a PR (`base: main`). If main has diverged, rebase the feature branch onto main rather than merging main into it.

    ## Playwright / Screenshots

    When using the Playwright MCP to take screenshots, **always save them to a subdirectory — never to the repository root**. Root-level PNG files accumulate as clutter and are hard to clean up.

    Use `.playwright-mcp/` or a clearly named subdirectory (e.g. `screenshots/`, `tmp/screenshots/`):

    ```
    # Good
    .playwright-mcp/login-page.png
    screenshots/checkout-flow.png

    # Bad
    login-page.png        # root-level clutter
    screenshot.png
    ```

    If the subdirectory does not exist yet, create it before saving. Add ephemeral screenshot directories to `.gitignore` if they should not be committed.

  '';
}
