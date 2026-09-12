# The actual prose lives in ./claude-md/, split by topic section, so each
# ~35-line CLAUDE.md rule lives in its own file. This path stays as a thin
# wrapper: codex.nix, opencode.nix, and claude-code-claude-md.nix all
# `import ./lib/claude-md-content.nix`, and the generated CLAUDE.md/AGENTS.md
# content itself names this exact path in its "Claude Config Files Are
# Generated" and "AGENTS.md/CLAUDE.md" sections — moving it would make the
# agent's own instructions point at a file that no longer exists.
import ./claude-md
