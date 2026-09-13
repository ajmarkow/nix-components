_: {
  # OpenCode loads global TypeScript plugins from this directory without an
  # opencode.json entry. Its documented tool.execute.before hook receives a
  # mutable output.args object; changing output.args.command therefore changes
  # the command that the built-in bash tool executes. See:
  # https://opencode.ai/docs/plugins/#from-local-files and
  # https://opencode.ai/docs/plugins/#dependencies
  #
  # Resolve secretty when the plugin starts instead of embedding its Nix store
  # path. This keeps the same degrade-gracefully contract as Claude Code: hosts
  # that import this agent module but omit the shared packages module still get
  # a working bash tool, only without the output-redaction backstop.
  xdg.configFile."opencode/plugins/secretty.ts".text = ''
    import type { Plugin } from "@opencode-ai/plugin"

    const shellQuote = (value: string): string =>
      "'" + value.replaceAll("'", "'\"'\"'") + "'"

    export const SecrettyPlugin: Plugin = async () => {
      const secretty = Bun.which("secretty")

      return {
        "tool.execute.before": async (input, output) => {
          if (input.tool !== "bash" || !secretty) return

          const command = output.args.command
          if (typeof command !== "string" || command.length === 0) return

          output.args.command = [
            shellQuote(secretty),
            '--config "$HOME/.config/secretty/config.yaml"',
            "--no-init-hints --strict run -- bash -c",
            shellQuote(command),
          ].join(" ")
        },
      }
    }
  '';
}
