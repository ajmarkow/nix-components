''
  ## Deploys = GitHub Actions CI

  **When the user says "deploy", "monitor deploy", "check the deploy", "did it deploy", "is it deployed", or anything about deployment status — the answer is always the GitHub Actions CI workflows for that repo.**

  There is no separate deploy system to check. Deployment happens through CI. Always use the `gh` CLI to inspect it:

  ```bash
  rtk gh run list --limit 10                        # recent runs across all workflows
  rtk gh run list --workflow=<name>.yml             # runs for a specific workflow
  rtk gh run view <run-id>                          # full details and logs for one run
  rtk gh run watch <run-id>                         # stream a run live until it finishes
  rtk gh workflow list                              # list all workflows in the repo
  ```

  **Decision tree:**
  - "Is it deployed?" → `gh run list --limit 5` and check if the latest run on the relevant branch succeeded
  - "Monitor the deploy" → `gh run watch <latest-run-id>` to stream it live
  - "What failed?" → `gh run view <run-id> --log-failed` to see only failing step logs
  - "Which workflows exist?" → `gh workflow list`

  Never check a separate dashboard, URL, or service unless the user explicitly names one. GitHub Actions is the source of truth.

  **Do not watch CI unless monitoring is necessary to complete the task or the user explicitly asks you to watch it.** Routine flake input bumps do not need CI monitoring. Unnecessary monitoring wastes tokens.

  If multiple unrelated jobs or repos fail the same way around the same time (e.g. runner-acquisition errors, timeouts), check https://www.githubstatus.com/ for an active incident before debugging the workflow config.
''
