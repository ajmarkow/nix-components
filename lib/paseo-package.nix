# Shared by nix-server (NixOS, linux) and nix-mac (nix-darwin): paseo release
# tags ship with a stale npmDepsHash, and node-pty's native addon is loaded by
# a dynamic require() (prebuilds/<platform>/pty.node) that @vercel/nft's
# static trace in scripts/trace-daemon.mjs misses, so the addon has to be
# copied back in by hand. One definition keeps both hosts' paseo derivation
# in lockstep instead of two independently drifting overrideAttrs blocks.
#
# npmDepsHash is optional: nix-server's linux value is already known-good
# (sha256-ObBdUmNSW+vDjzA7EbCDfZrB0nYDmcWmWe+UCoTMh/M=). The equivalent
# aarch64-darwin hash has not been verified by a real build, so a caller that
# doesn't know it yet should omit it and let paseo's own npm-deps.hash file
# stand -- a wrong placeholder hash would guarantee a build failure, where
# the untouched default merely might.
{
  paseoPackage,
  npmDepsHash ? null,
}:
paseoPackage.overrideAttrs (old: {
  npmDeps =
    if npmDepsHash == null then
      old.npmDeps
    else
      old.npmDeps.overrideAttrs (_: {
        outputHash = npmDepsHash;
      });

  postInstall = (old.postInstall or "") + ''
    src=$(find . -type d -path "*/node-pty/prebuilds" -not -path "*/prebuilds/*" | head -n1)
    if [ -z "$src" ]; then
      echo "node-pty prebuilds directory not found in build tree" >&2
      exit 1
    fi
    for dst in $(find "$out" -type d -name node-pty); do
      cp -r "$src" "$dst/prebuilds"
    done
    if ! find "$out" -name pty.node | grep -q .; then
      echo "pty.node still missing from \$out after copy" >&2
      exit 1
    fi
  '';
})
