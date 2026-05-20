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
  '';
}
