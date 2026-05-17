# Deploying the flake update CI pipeline

This pipeline automatically opens pull requests in consumer repos whenever `nix-components` is updated.

## How it works

1. A commit lands on `main` in this repo (`nix-components`).
2. `notify-consumers.yml` fires a `repository_dispatch` event at each listed consumer repo.
3. `update-flake-lock.yml` in the consumer repo wakes up, runs `nix flake update nix-components`, and opens (or force-pushes) a PR if `flake.lock` changed.
4. A developer reviews and merges the PR.

---

## Setup: this repo (`nix-components`)

### 1. Create a Personal Access Token (PAT)

The dispatch workflow needs a PAT with write access to each consumer repo so it can trigger `repository_dispatch` events.

- Go to **GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens**
- Click **Generate new token**
- Set **Resource owner** to the org or account that owns the consumer repos
- Under **Repository access**, select each consumer repo explicitly
- Grant the following permission:
  - **Contents** → Read and write (needed to trigger `repository_dispatch`)
- Copy the token value — you will not see it again

### 2. Add the PAT as a secret in this repo

- Go to this repo on GitHub → **Settings → Secrets and variables → Actions**
- Click **New repository secret**
- Name: `FLAKE_CONSUMER_PAT`
- Value: paste the token from step 1

### 3. Install the workflow

Copy `notify-consumers.yml` into `.github/workflows/` in this repo:

```
cp ci-workflows/notify-consumers.yml .github/workflows/notify-consumers.yml
```

### 4. Add consumer repos to the matrix

Edit `.github/workflows/notify-consumers.yml` and replace the placeholder entries under `matrix.consumer` with your actual consumer repos:

```yaml
matrix:
  consumer:
    - your-org/home-config
    - your-org/nixos-config
```

---

## Setup: each consumer repo

### 1. Install the workflow

Copy `consumer/update-flake-lock.yml` into `.github/workflows/` in the consumer repo:

```
cp ci-workflows/consumer/update-flake-lock.yml .github/workflows/update-flake-lock.yml
```

### 2. Verify the input name matches

The workflow calls `nix flake update nix-components`. If your consumer refers to this flake under a different input name, update that line:

```yaml
- name: Update nix-components input
  run: nix flake update <your-input-name>
```

To find the input name, check the consumer's `flake.nix`:

```nix
inputs = {
  nix-components.url = "github:your-org/nix-components";  # <-- this key is the input name
};
```

### 3. No additional secrets required

The consumer workflow uses the built-in `GITHUB_TOKEN`, which has permission to open PRs within the same repo. No extra secrets are needed on the consumer side.

---

## Testing

### Test the consumer workflow manually

In a consumer repo, go to **Actions → Update flake.lock → Run workflow**. This simulates what happens when a dispatch event arrives.

### Test the dispatch workflow manually

In this repo, go to **Actions → Notify consumers of flake update → Run workflow**. Check that each consumer repo receives the event under its **Actions** tab.

### Verify the PAT is working

If dispatches are silently failing, check the `notify-consumers` run logs. A 404 or 403 on the dispatch step means the PAT either lacks access to the target repo or has expired.

---

## Ongoing maintenance

| Task | Where |
|---|---|
| Add a new consumer repo | Edit `matrix.consumer` in `notify-consumers.yml` and install the consumer workflow in that repo |
| Remove a consumer repo | Remove it from the matrix |
| PAT expires | Rotate the token and update the `FLAKE_CONSUMER_PAT` secret |
| Update all inputs, not just this one | Change `nix flake update nix-components` to `nix flake update` in the consumer workflow |
