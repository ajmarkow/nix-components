# Shared prose for both Claude Code's CLAUDE.md and opencode's AGENTS.md.
#
# This is a plain string, not a home-manager module — do NOT move it into
# ../modules/ directly; home-modules.nix auto-imports every top-level .nix
# file there as a home module, which would break on a bare string. Reading
# it back out of `config.home.file.".claude/CLAUDE.md".text` from a second
# module (as opencode.nix originally did) causes infinite recursion, because
# home-manager's `programs.opencode.context` folds into `xdg.configFile`,
# which folds back into `home.file` — so `home.file` can't be evaluated
# while it's still evaluating itself. Importing this file directly sidesteps
# that: it's just a string, independent of `config`.
(import ./bash-tool-guidelines-mandatory.nix)
+ "\n"
+ (import ./critical-use-rtk-only-for-its-supported-subcommand.nix)
+ "\n"
+ (import ./critical-use-semble-and-rg-for-search-never-grep-o.nix)
+ "\n"
+ (import ./context-session-discipline.nix)
+ "\n"
+ (import ./fetching-web-content.nix)
+ "\n"
+ (import ./response-style-asd-ste100.nix)
+ "\n"
+ (import ./decision-points-use-askuserquestion.nix)
+ "\n"
+ (import ./agentic-task-board-mandatory.nix)
+ "\n"
+ (import ./inter-agent-messaging.nix)
+ "\n"
+ (import ./tool-availability-nix-shell-optimization.nix)
+ "\n"
+ (import ./missing-tools-self-healing-protocol.nix)
+ "\n"
+ (import ./never-run-rebuild-commands-this-is-a-management-se.nix)
+ "\n"
+ (import ./never-ssh-to-a-host.nix)
+ "\n"
+ (import ./never-kill-or-restart-a-container-without-approval.nix)
+ "\n"
+ (import ./this-host-is-nixos-host-read-its-logs-yourself.nix)
+ "\n"
+ (import ./claude-config-files-are-generated-edit-the-nix-sou.nix)
+ "\n"
+ (import ./mcp-servers.nix)
+ "\n"
+ (import ./a-repos-agentsmd-claudemd-is-for-repo-specific-fac.nix)
+ "\n"
+ (import ./nix-declarative-configuration-philosophy.nix)
+ "\n"
+ (import ./flake-updates-targeted-by-default.nix)
+ "\n"
+ (import ./build-verification-never-trust-a-pipes-exit-code.nix)
+ "\n"
+ (import ./deploys-github-actions-ci.nix)
+ "\n"
+ (import ./never-remove-ci-checks-without-explicit-instructio.nix)
+ "\n"
+ (import ./git-workflow.nix)
+ "\n"
+ (import ./branch-merges-main-is-always-the-base.nix)
+ "\n"
+ (import ./never-print-infisical-secrets-as-plaintext.nix)
+ "\n"
+ (import ./plan-files.nix)
+ "\n"
+ (import ./aws-cli-requires-a-plan-first.nix)
+ "\n"
+ (import ./playwright-screenshots.nix)
