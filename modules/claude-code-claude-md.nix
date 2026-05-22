{
  home.file.".claude/CLAUDE.md".text = ''
    # Bash Tool Guidelines — MANDATORY

    ## ⚠️ CRITICAL: Every Bash command MUST start with `rtk`

    **No exceptions.** Prefix every single Bash tool call with `rtk`. This applies to ALL commands: git, cp, mkdir, ls, grep, cat, find, npm, nix, gh, paseo — everything. Unsupported commands pass through unchanged, so there is zero downside and no reason to ever omit it.

    ```bash
    # CORRECT — always do this:
    rtk git status
    rtk git push origin main
    rtk cp file.txt dest/
    rtk mkdir -p .github/workflows
    rtk ls ~/projects
    rtk paseo ls

    # WRONG — never do this:
    git status
    cp file.txt dest/
    mkdir -p .github/workflows
    ```

    ## ⚠️ CRITICAL: Prefer `rg` (ripgrep) over `grep`

    **Always use `rg`** for file searching instead of `grep`. It's faster, respects .gitignore, handles directories recursively by default, and provides better output formatting. No exceptions.

    ```bash
    # CORRECT — always do this:
    rtk rg "pattern" .
    rtk rg "pattern" src/
    rtk rg -t rust "const "

    # WRONG — never do this:
    rtk grep "pattern" -r .
    rtk grep -r "pattern" src/
    ```

    ## Fetching Web Content

    Always prefer `defuddle` over `WebFetch` when reading URLs (articles, docs, blog posts, any standard web page). It strips navigation and clutter, reducing token usage.

    ```bash
    rtk defuddle parse <url> --md
    ```

    Only fall back to `WebFetch` if defuddle is unavailable or the URL is not a standard web page (e.g. raw JSON APIs, authenticated services).

    ## Inter-Agent Messaging

    When the user asks you to message, notify, or send something to another agent or repo, **use `paseo`** — not files, git, or any other mechanism.

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

    ## Tool Availability & nix-shell Optimization

    **Before wrapping a command in nix-shell, check if the tool is already available in PATH.** Tools already in the current environment do not need nix-shell.

    ### Check Tool Availability

    Use `which <tool>` to verify a tool is installed before using nix-shell:

    ```bash
    # Check if curl is available
    rtk which curl

    # If available (exit code 0), use it directly:
    rtk curl https://example.com

    # Only use nix-shell if not found:
    rtk nix-shell -p curl --run "curl https://example.com"
    ```

    ### Common Tools Already Available

    Many tools are already in `/etc/profiles/per-user/paseo/bin/` and other standard PATH locations. Examples: `curl`, `git`, `jq`, `python3`, `node`, `grep`, `sed`, `awk`, `find`, `ls`. Check before assuming nix-shell is needed.

    ### Pattern

    - ❌ `NIXPKGS_ALLOW_UNFREE=1 rtk nix-shell -p curl --run "curl ..."`
    - ✅ `rtk which curl && rtk curl ...` (if available)
    - ✅ `rtk nix-shell -p curl --run "curl ..."` (only if not found)

    This reduces overhead and keeps command execution fast. Reserved only for tools guaranteed to be unavailable elsewhere (e.g., ngrok, specialized build tools, or specific versions).

    ## Missing Tools — Self-Healing Protocol

    When a command fails with **"command not found"**, **"No such file or directory"** (ENOENT on a binary), or **"spawn X ENOENT"**, treat it as a signal to fix the environment declaratively rather than working around it.

    ### Protocol

    1. **Identify the missing binary** from the error (e.g. `sh`, `make`, `sed`).
    2. **Find its nixpkgs package**: `rtk nix-locate --top-level --whole-name bin/<binary>` or check [search.nixos.org](https://search.nixos.org/packages).
    3. **Add it to `/var/lib/paseo/paseo-projects/nix-server/modules/paseo.nix`** under `systemd.services.paseo.path`:
       ```nix
       pkgs.<package-name>
       ```
    4. **Verify the flake evaluates**: `cd ~/paseo-projects/nix-server && rtk nix flake check --no-build`
    5. **Commit and push**, then **trigger redeploy**:
       ```bash
       cd ~/paseo-projects/nix-server
       rtk git add modules/paseo.nix && rtk git commit -m "fix(paseo): add <pkg> to service PATH"
       rtk git push
       rtk sudo systemctl start nixos-rebuild-switch
       ```
    6. **Wait for the deploy to complete**, then retry the original task.

    ### Why declarative, not nix-shell

    Ad-hoc `nix-shell -p foo --run "..."` works once but leaves the environment broken for the next session and for other agents. Adding to `paseo.nix` fixes it permanently for all future sessions. **Always fix the root cause.**

    ## Nix & Declarative Configuration Philosophy

    Prefer declarative configuration and environment management over imperative commands. This applies across all projects and tools.

    ### Core Principle

    **Always edit the source, never the output.** Generated files, installed packages, and applied configurations should never be modified directly. Changes belong in the declarative source:
    - `.nix` files for system/home-manager configuration
    - `devenv.nix` for development environments
    - Configuration modules for tools and services

    Then regenerate by running the appropriate apply command (`home-manager switch`, `nixos-rebuild switch`, `devenv up`, etc.).

    ### Pattern Examples

    - ❌ `nix-env -i package` → ✅ Add to `devenv.packages` or Nix module
    - ❌ Edit generated config files → ✅ Modify the `.nix` source
    - ❌ Manual `.env` setup → ✅ Define in `devenv.nix`
    - ❌ Imperative `mkdir` or `ln -s` → ✅ Use Nix `home.file` or `home.sessionVariables`

    **Why?** Reproducibility, auditability, and self-documentation. Configuration becomes code that survives rebuilds and can be version-controlled.

    ### Nix Flakes

    **Run `rtk nix flake check` before every commit when working in a flake repo.** The check must pass before the commit proceeds.
  '';
}
