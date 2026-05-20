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

    Find the target agent, then send:
    ```bash
    paseo ls -a -g                         # list all agents across all directories
    paseo send <id> "message or task"      # id can be shortened if unambiguous
    ```

    If no agent is running for the target, start one:
    ```bash
    paseo run "task" --detach --name <name>
    ```

    Prefer `paseo send` to an existing agent over starting a duplicate. Other commands:
    ```bash
    paseo attach <id>   # stream output live
    paseo wait <id>     # block until agent finishes
    paseo stop <id>     # terminate
    ```
  '';
}
