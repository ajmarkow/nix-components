---
name: diff-viewer
description: Use when about to show the user a diff or set of changes and a rendered web view would be clearer than raw terminal output — renders it as HTML via diff2html and serves it at a tailnet URL. Also use when the user asks to share, link, or view a diff in the browser.
argument-hint: [git-diff-args]
allowed-tools: [Read, Bash, Glob]
user-invocable: true
---

Render a diff as HTML and serve it from this host's diff-viewer service, so the user can open a link instead of reading terminal output. Works on any host that has the `diff-viewer` home-manager module (nix-components) applied — the URL is resolved from this host's own Tailscale identity at run time, not hardcoded.

## Steps

1. Check `$ARGUMENTS` is a literal `git diff` argument — a ref spec (`main..HEAD`), a flag (`--staged`), a path filter, or empty. It is spliced straight into `git diff`, so a prose description is not valid. If the user described what they want in prose, translate it to the equivalent git-diff arguments first, or use no arguments for the working-tree diff.

2. Run the renderer. It takes the same arguments as `git diff`:
   ```bash
   diff-viewer-render $ARGUMENTS
   ```
   It prints the tailnet URL on success. Report that URL to the user, and mention that the index link it prints lists past diffs and that files expire automatically after 30 days.

That is the whole skill. Do not assemble the pipeline by hand — `diff-viewer-render` owns diff generation, format validation, rendering, theming, and post-render verification, with `git` and `diff2html` pinned to store paths.

## Gotchas

- **Never run `git diff` yourself and pipe it into `diff2html`.** Two separate wrappers corrupt that pipeline on these hosts, and both are silent. The rtk PreToolUse hook rewrites a bare `git diff` into `rtk git diff`, and interactive shells also carry a `git` function — so typing plain `git diff` is not enough to avoid it. rtk's pretty-printer emits a human summary (stat lines, a `--- Changes ---` header, `+3 -3` footers) with no `diff --git` headers. diff2html then parses zero files, exits 0, and still writes a ~298KB page containing only its template. The file is written, served, and returns HTTP 200; the only visible symptom is "Files changed (0)" once someone opens it. `diff-viewer-render` avoids this by calling a pinned git binary directly.
- A served 200 is not proof the render worked. `diff-viewer-render` already greps the generated HTML for a known changed filename and deletes the page rather than serving a misleading one, so trust its exit code, not the HTTP status.

## Exit codes

- `0` — rendered; the URL is on stdout.
- `3` — the diff is empty. Tell the user there is nothing to show. Not an error.
- `1` — a real failure, with the reason on stderr. Report it rather than working around it. Causes include: `$ARGUMENTS` was not valid git-diff arguments (git's own error is included), the input was not unified diff format, render verification failed, `~/diff-viewer` is missing, or the tailnet name could not be resolved. A missing `~/diff-viewer`, absent `diff-viewer-render`, or `tailscale status --json` error all mean the `diff-viewer` home-manager module is not applied on this host.

## Notes

- Diffs only leave the tailnet if a device is on it — there's no public/LAN exposure and no separate auth layer, matching Tailscale's own access model.
- If the diff renders but the URL 404s, the local server may be up but not yet registered with `tailscale serve` — this happens when the host's tailscaled operator hasn't been granted for this user yet (`services.tailscale.extraSetFlags = [ "--operator=<user>" ]` on the system side). Report this rather than trying to grant it yourself.
