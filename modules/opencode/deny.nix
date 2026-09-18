_: {
  # Bash deny class shared with Claude Code's block-ssh-rg-cd.sh. Thrown
  # errors abort the tool call (same contract as the documented .env
  # protection example). Deny-only: this plugin never rewrites, so it
  # cannot race the secretty redaction wrap in ./secretty.nix. Wired
  # together with secretty and memory-guard in ./hooks.nix.
  #
  # Keep the git carve-out for ssh: git cannot open an interactive host
  # connection and routinely carries "ssh" as free text (commit messages,
  # grep patterns, branch names).
  xdg.configFile."opencode/plugins/deny.ts".text = builtins.readFile ./deny.ts;
}
