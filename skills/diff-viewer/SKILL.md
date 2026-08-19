---
name: diff-viewer
description: Use when about to show the user a diff or set of changes and a rendered web view would be clearer than raw terminal output — renders it as HTML via diff2html and serves it at a tailnet URL. Also use when the user asks to share, link, or view a diff in the browser.
argument-hint: [git-diff-args]
allowed-tools: [Read, Bash, Glob]
user-invocable: true
---

Render a diff as HTML and serve it from this host's diff-viewer service, so the user can open a link instead of reading terminal output. Works on any host that has the `diff-viewer` home-manager module (nix-components) applied — the URL is resolved from this host's own Tailscale identity at run time, not hardcoded.

## Steps

1. Resolve the diff. Pass `$ARGUMENTS` straight through to `git diff` — this covers refs (`main..HEAD`), `--staged`, path filters, or nothing (working-tree diff):
   ```bash
   rtk git diff $ARGUMENTS
   ```
   If the diff is empty, tell the user there's nothing to show and stop. Do not write an empty file.

2. Build a unique filename: `<repo-name>-<ref-slug>-<timestamp>.html`. Derive the repo name from the toplevel directory, slugify `$ARGUMENTS` (or omit that part if empty), and use `date +%Y%m%dT%H%M%S` for the timestamp so files sort chronologically and never collide.

3. Render straight into the served directory:
   ```bash
   rtk git diff $ARGUMENTS | diff2html -i stdin -o stdout -s side --cs dark -t "<repo-name>: <short description>" > ~/diff-viewer/<filename>
   ```
   `-s side` gives a side-by-side view; drop it for the default line-by-line view if the diff is very wide. `--cs dark` keeps diff2html's own dark-mode structure so the Catppuccin Frappé override in the next step reads cleanly. `diff2html` is a plain binary — do not prefix it with `rtk`.

   diff2html has no built-in Catppuccin theme, so inject one as a `<style>` block before `</head>`. Make sure `frappe.css` (shipped alongside this skill) is copied to `~/diff-viewer/frappe.css` once (`cp -n <skill-dir>/frappe.css ~/diff-viewer/frappe.css`), then splice it in:
   ```bash
   python3 -c "
   import sys
   html = open(sys.argv[1]).read()
   css = open(sys.argv[2]).read()
   html = html.replace('</head>', f'<style>{css}</style></head>', 1)
   open(sys.argv[1], 'w').write(html)
   " ~/diff-viewer/<filename> ~/diff-viewer/frappe.css
   ```

4. Resolve this host's tailnet URL and report it to the user. The diff-viewer module serves on a non-443 tailnet HTTPS port (default `8443`, host-configurable via `services.diffViewer.tailnetPort` — never 443, see the comment in `modules/diff-viewer.nix` for why), so read the actual registered port from `tailscale serve status` rather than assuming it:
   ```bash
   tailscale status --json | python3 -c "import json,sys; print(json.load(sys.stdin)['Self']['DNSName'].rstrip('.'))"
   tailscale serve status --json | python3 -c "import json,sys; print(next(iter(json.load(sys.stdin).get('TCP',{}))))"
   ```
   The full URL is `https://<that-dns-name>:<that-port>/diffs/<filename>`.

5. Mention, briefly, that the directory listing at `https://<that-dns-name>:<that-port>/diffs/` shows past diffs, and that files expire automatically after 30 days.

## Notes

- Diffs only leave the tailnet if a device is on it — there's no public/LAN exposure and no separate auth layer, matching Tailscale's own access model.
- If `~/diff-viewer` doesn't exist, `diff2html` isn't found, or `tailscale status --json` errors, the `diff-viewer` home-manager module (nix-components) isn't applied on this host — report that rather than working around it.
- If the diff is rendered but the URL 404s, the local server may be up but not yet registered with `tailscale serve` — this happens when the host's tailscaled operator hasn't been granted for this user yet (`services.tailscale.extraSetFlags = [ "--operator=<user>" ]` on the system side). Report this rather than trying to grant it yourself.
