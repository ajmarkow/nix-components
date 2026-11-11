# Single source of truth for binary caches. Consumed by:
#   - os-modules/determinate/shared.nix (host nix.conf)
#   - lib.mkCacheParityCheck (fails when a flake's literal nixConfig drifts)
#   - pkgs/nix-cache-doctor.nix
# nixConfig in a flake.nix must be a literal attrset and cannot import this
# file, so the parity check is what keeps those copies honest.
# One wrong character in a key makes nix skip the cache with only a warning,
# so copy entries rather than retyping them.
{
  substituters = [
    "https://cache.nixos.org"
    "https://nix-community.cachix.org"
    "https://ajmarkow.cachix.org"
    "https://claude-code.cachix.org"
    "https://codex-cli.cachix.org"
    "https://devenv.cachix.org"
  ];

  trustedPublicKeys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCUSeBc="
    "ajmarkow.cachix.org-1:6HxkDVfkPWy2esadGzUIj6vGzmMuQOgz3mimKT7J9sw="
    "claude-code.cachix.org-1:YeXf2aNu7UTX8Vwrze0za1WEDS+4DuI2kVeWEE4fsRk="
    "codex-cli.cachix.org-1:1Br3H1hHoRYG22n//cGKJOk3cQXgYobUel6O8DgSing="
    "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
  ];
}
