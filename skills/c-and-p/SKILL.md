---
name: c-and-p
description: Commit all staged and unstaged changes using a conventional commit message, then push to the current remote branch.
user-invocable: true
model: sonnet
---

Commit all staged and unstaged changes using a conventional commit message, then push.

Steps:
1. Run `git status` and `git diff` to understand what changed.
2. Stage all relevant changes (prefer specific files over `git add -A`).
3. Write a conventional commit message: `<type>(<scope>): <short summary>`
   - Types: feat, fix, docs, style, refactor, perf, test, build, ci, chore
   - Scope is optional but encouraged
   - Summary should be lowercase, imperative, no period
4. Commit the changes.
5. Push to the current remote tracking branch (or `origin <current-branch>` if unset).
