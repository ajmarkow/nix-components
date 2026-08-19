---
name: deploy-nix-components
description: Use when asked to deploy, ship, or release a nix-components change, propagate nix-components to nix-server, or bump the nix-components flake input on nix-server.
---

# Deploy nix-components → nix-server

Ship a nix-components change: verify and push this repo, then bump the `nix-components` flake input on nix-server so its CI deploys it. Every command below was run and verified.

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

## 2. Bump the input on nix-server

Run `bump-nix-components` from the nix-server repo. It updates only the `nix-components` input, runs `nix flake check --no-build`, commits `flake.lock`, and pushes to trigger CI:

```bash
cd /var/lib/paseo/paseo-projects/nix-server && bump-nix-components --push
```

Drop `--push` to stop at the commit, or add `--dry-run` to see the pending rev change without touching the repo. It refuses to run outside a repo that already locks `nix-components`, so it cannot rewrite the wrong flake.

Two non-failures to expect:

- `already up to date at <sha>` (exit 0) — step 1's push hasn't propagated to GitHub yet, or you never pushed it. Re-check step 1, then retry.
- `flake.lock has uncommitted changes` (exit 1) — commit or discard that edit first; the script won't fold it into the bump commit.

If a `nix flake check` failure aborts the bump, the modified `flake.lock` is left in place on purpose so you can inspect it — the script prints the exact revert command.

**If `bump-nix-components` is not on PATH**, that host hasn't deployed a nix-components generation containing it yet (it ships via `scripts/`, which `modules/packages.nix` auto-installs — it is not a flake package, so `nix run` won't reach it). Fall back to the manual sequence once, then it'll be present:

```bash
cd /var/lib/paseo/paseo-projects/nix-server && rtk nix flake update nix-components
cd /var/lib/paseo/paseo-projects/nix-server && rtk nix flake check --no-build
cd /var/lib/paseo/paseo-projects/nix-server && rtk git commit -m "chore(flake): bump nix-components" flake.lock && rtk git push origin main
```

## 3. Confirm the bump

`bump-nix-components` prints the bump on success, e.g. `Committed: nix-components e9f0716 -> bfa6b1f`. Confirm the new rev matches the SHA you noted in step 1. Get the nix-server commit SHA for step 4:

```bash
cd /var/lib/paseo/paseo-projects/nix-server && rtk git rev-parse --short HEAD
```

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
- The shell CWD resets between Bash tool calls — prefix each `gh` command with `cd /var/lib/paseo/paseo-projects/nix-server &&`, or the run lookup hits the wrong repo. The same applies to `bump-nix-components`, which acts on the current repo.
- Old Deploy runs for previous SHAs may show `success` — always match `headSha` to the new nix-server commit before declaring victory.

## Troubleshooting

- `gh run list` shows no run for the new SHA → CI hasn't picked up the push yet; re-list after a few seconds.
- Check run `conclusion: action_required` → the run needs manual approval in GitHub; tell the user rather than waiting forever.
