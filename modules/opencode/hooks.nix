_: {
  # Opencode hook wiring: three sibling plugin files, one per concern, so
  # each stays reviewable on its own. All are deny-only except the
  # secretty redaction wrap, and deny/guard plugins never rewrite — only
  # throw — so there is no competing-rewrite race despite plugins running
  # in load order against the same original args.
  imports = [
    ./secretty.nix
    ./deny.nix
    ./memory-guard.nix
  ];
}
