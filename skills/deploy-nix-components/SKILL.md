---
name: deploy-nix-components
description: Use when asked to deploy, ship, or release a nix-components change, propagate nix-components to nix-server, or bump the nix-components flake input on nix-server.
---

# Deploy nix-components → nix-server

Ship a nix-components change: verify and push this repo, then have the nix-server agent bump its `nix-components` flake input so nix-server CI deploys it. Every command below was run and verified. Prefix all Bash with `rtk` except `paseo`.

## 1. Verify and push nix-components

From the nix-components repo root:

```bash
rtk nix flake check --no-build
```

Must pass before committing. Then commit and push (skills under `skills/` are auto-discovered by `modules/claude-code.nix` — no wiring needed):

```bash
rtk git add <files> && rtk git commit -m "..." && rtk git push origin main
rtk git rev-parse --short HEAD   # note this SHA — you'll verify the bump against it
```

## 2. Message nix-server via paseo

Find an existing nix-server agent (CWD `~/paseo-projects/nix-server`):

```bash
paseo ls -a -g
```

- If an idle/running agent exists there, reuse it: `paseo send <id> "<prompt>"`.
- Otherwise spawn one — **always** with `--cwd`:

```bash
paseo run "<prompt>" --cwd /var/lib/paseo/paseo-projects/nix-server \
  --detach --name bump-nix-components --model sonnet
```

Verified prompt:

```
Bump the nix-components flake input in this repo: run 'rtk nix flake update nix-components',
verify with 'rtk nix flake check --no-build', then commit the flake.lock change with a
conventional commit message and push to main to trigger CI. Report the pushed commit SHA when done.
```

## 3. Wait for the agent and confirm the bump

```bash
paseo wait <id>
```

**Gotcha:** `paseo wait` returns when the agent goes *idle*, which can happen mid-task (e.g. while its background `nix flake check` is still running). Check its last activity; if it hasn't pushed yet, run `paseo wait <id>` again.

Confirm the bumped input SHA matches the SHA you noted in step 1 (the agent reports it, e.g. "bumped to `f7646bc`"). Get the nix-server commit SHA from the agent's report.

## 4. Watch nix-server CI until deployed

nix-server has two workflows: **Check** runs on push, and **Deploy** only queues *after* Check succeeds — so watching Check alone is not enough.

```bash
cd /var/lib/paseo/paseo-projects/nix-server && \
  rtk gh run list --limit 3 --json databaseId,headSha,status,conclusion,workflowName
```

Find the Check run whose `headSha` matches the nix-server commit, watch it, then find and watch the Deploy run that queues afterward:

```bash
cd /var/lib/paseo/paseo-projects/nix-server && rtk gh run watch <check-run-id> --exit-status
cd /var/lib/paseo/paseo-projects/nix-server && \
  rtk gh run list --limit 5 --json databaseId,headSha,status,conclusion,workflowName   # Deploy run appears here
cd /var/lib/paseo/paseo-projects/nix-server && rtk gh run watch <deploy-run-id> --exit-status
```

`--exit-status` makes `gh run watch` exit non-zero on failure. When the Deploy run completes successfully, the change is live on nix-server.

## Gotchas

- **Never rebuild locally** (`home-manager switch` etc.) — this is a management server; CI is the only deploy path.
- The shell CWD resets between Bash tool calls — prefix each `gh` command with `cd /var/lib/paseo/paseo-projects/nix-server &&`, or the run lookup hits the wrong repo.
- `paseo run` defaults to the caller's directory; a repo path in the prompt text does **not** set the agent's CWD — `--cwd` is mandatory.
- Old Deploy runs for previous SHAs may show `success` — always match `headSha` to the new nix-server commit before declaring victory.

## Troubleshooting

- `gh run list` shows no run for the new SHA → CI hasn't picked up the push yet; re-list after a few seconds.
- Check run `conclusion: action_required` → the run needs manual approval in GitHub; tell the user rather than waiting forever.
