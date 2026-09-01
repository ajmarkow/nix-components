---
name: deploy-nix-components
description: Use when asked to deploy, ship, or release a nix-components change to downstream flakes.
---

# Deploy nix-components

Bump the `nix-components` flake input on every downstream repo, commit `flake.lock`, and push to trigger CI.

For each repo run `bump-nix-components --push` from inside that repo. It updates only `nix-components`, checks, commits `flake.lock`, and pushes.

```bash
for repo in nix-server nix-mac nix-pixelbook; do
  echo "=== $repo ==="
  if command -v bump-nix-components >/dev/null 2>&1; then
    (cd /var/lib/paseo/paseo-projects/$repo && bump-nix-components --push)
  else
    rtk nix flake update nix-components --flake /var/lib/paseo/paseo-projects/$repo
    rtk nix flake check --no-build /var/lib/paseo/paseo-projects/$repo
    rtk git -C /var/lib/paseo/paseo-projects/$repo add flake.lock
    rtk git -C /var/lib/paseo/paseo-projects/$repo commit -m "chore(flake): bump nix-components"
    rtk git -C /var/lib/paseo/paseo-projects/$repo push
  fi
done
```
