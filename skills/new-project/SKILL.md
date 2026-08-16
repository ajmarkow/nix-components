---
name: new-project
description: Use when the user wants to start a new project or repo — creating the directory, git repo, GitHub remote, and paseo workspace.
argument-hint: <name> [--public]
allowed-tools: [Bash]
user-invocable: true
---

Run the `new-project` command-line tool to do this. It is already on PATH.

```bash
new-project <name> [--public] [--parent <dir>] [--desc <text>] [--json]
```

- Repos are private by default. Pass `--public` only if the user asked for a public repo.
- Do not run `git init`, `gh repo create`, or `paseo workspace create` yourself — `new-project` does all of it, in the right order, and reports `path`, `repo_url`, and `workspace_id` when it finishes.
- Report those three values back to the user.
