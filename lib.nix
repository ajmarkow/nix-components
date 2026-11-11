_: {
  flake.lib.mkSecretsApp = import ./lib/infisical-secrets.nix;
  flake.lib.mkPaseoPackage = import ./lib/paseo-package.nix;
  flake.lib.caches = import ./caches.nix;
  flake.lib.mkCacheParityCheck = import ./lib/cache-parity-check.nix;
}
