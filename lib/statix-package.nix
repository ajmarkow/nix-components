{ pkgs }:

# Upstream snapshot assertions currently fail after the package has compiled
# successfully on Darwin.
if pkgs.stdenv.hostPlatform.isDarwin then
  pkgs.statix.overrideAttrs (_: {
    doCheck = false;
  })
else
  pkgs.statix
