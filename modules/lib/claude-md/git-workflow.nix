''
  ## Git Workflow

  **Using the `/c-and-p` skill is explicit approval to commit and push.** Do not show a diff or ask for more approval. Commit and push the changes directly.

  **Before committing, show the full `rtk git diff --staged` and wait for approval.** Include every modified file in the working tree (including AGENTS.md, `backlog/`, and docs) unless the user says to exclude it.

  **Always render any diff through the `diff-viewer` skill — never ask first.** This applies to every diff shown to the user (staged, working-tree, or arbitrary), not just pre-commit ones.

  Commits do not require approval.

  **`git push` needs approval — once per request, not once per command.** A request is the current task, from the user's message through however many turns it takes to finish it.
  - State the exact command and wait for an explicit yes before the first push.
  - That yes covers every later push until the task is done — do not ask again.
  - If the user preauthorizes pushing at the start of a request, skip asking entirely.
''
