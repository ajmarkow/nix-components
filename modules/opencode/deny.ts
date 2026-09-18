import type { Plugin } from "@opencode-ai/plugin";

// Bash deny class shared with Claude Code's block-ssh-rg-cd.sh. Thrown
// errors abort the tool call (same contract as the documented .env
// protection example). Deny-only: this plugin never rewrites, so it
// cannot race the secretty redaction wrap in secretty.ts — both plugins
// run in load order against the same original args, and a deny from
// either one blocks the call.
//
// Keep the git carve-out for ssh: git cannot open an interactive host
// connection and routinely carries "ssh" as free text (commit messages,
// grep patterns, branch names).
const denyPatterns: Array<[RegExp, string]> = [
  [/(^|[;&|(`$\s])rg\b/, "use rtk semble search instead of rg."],
  [
    /(^|[;&|(`$\s])(grep|egrep|fgrep)\s+[^\s;&|]*-[a-zA-Z]*[rR]/,
    "use rtk semble search instead of grep -r.",
  ],
  [
    /(^|[;&|(`$\s])find\s+[^\s;&|]*-name\b/,
    "use rtk semble search instead of find -name.",
  ],
  [
    /(^|[;&|(`$\s])ps\s+(aux|[^\s]*[uU][^\s]*|-([^\s]*[fF][^\s]*|[^\s]*[eE][^\s]*))([^\w]|$)/,
    "no argv-revealing ps (ps aux / ps -ef). Use ps -o pid,comm= instead.",
  ],
  [
    /(>>?|>)\s*[^;&|]*\/memory\//,
    "no shell writes to auto-memory (prompt must contain explicit remember approval).",
  ],
  [
    /(^|[;&|(`$\s])(nixos-rebuild|home-manager)\s+switch\b/,
    "never rebuild locally — commit+push, CI deploys.",
  ],
];

const sshPattern = /(^|[^a-zA-Z0-9._-])(ssh|scp|sftp)([\s]|$)/;

const isGitCommand = (command: string): boolean => {
  const scan = command.replace(/^\s*GIT_SSH_COMMAND=("[^"]*"|\S+)\s*/, "");
  return /^(git\s|rtk\s+git\s|\S*\/git\s)/.test(scan);
};

export const DenyPlugin: Plugin = async () => {
  return {
    "tool.execute.before": async (input, output) => {
      if (input.tool !== "bash") return;

      const command = output.args.command;
      if (typeof command !== "string" || command.length === 0) return;

      // git grep is version-controlled code search, not filesystem
      // spelunking — strip it before matching the recursive-grep rule.
      // Explicit -o carve-out for ps: `ps -o pid,comm=` chooses safe
      // columns, so it stays allowed even alongside other flags.
      const nonGitGrep = command.replace(
        /git\s+(grep|egrep|fgrep)/g,
        "git-GREP-EXEMPT",
      );
      const hasExplicitOutput = /(^|[;&|(`$\s])ps\s+[^;&|]*-o\s/.test(command);
      for (const [pattern, reason] of denyPatterns) {
        const target = pattern.source.includes("(grep|egrep|fgrep)\\s")
          ? nonGitGrep
          : command;
        if (pattern.test(target)) {
          if (hasExplicitOutput && reason.startsWith("no argv-revealing ps"))
            continue;
          throw new Error("Blocked: " + reason);
        }
      }
      if (!isGitCommand(command) && sshPattern.test(command)) {
        throw new Error(
          "Blocked: no direct ssh/scp/sftp to a host. ssh-add, ssh-keygen, .ssh/ paths and git commands are allowed.",
        );
      }
    },
  };
};
