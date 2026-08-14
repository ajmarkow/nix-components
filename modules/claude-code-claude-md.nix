# The actual prose lives in ./lib/claude-md-content.nix, shared with
# opencode.nix's AGENTS.md (programs.opencode.context). Do not inline the
# text back into home.file here and read it via `config.home.file...text`
# from another module — that path caused an infinite-recursion eval failure
# (home-manager's programs.opencode.context folds into xdg.configFile, which
# folds back into home.file, so home.file can't finish evaluating while it's
# still evaluating itself). Both modules must import the plain string
# directly instead.
{
  home.file.".claude/CLAUDE.md".text = import ./lib/claude-md-content.nix;
}
