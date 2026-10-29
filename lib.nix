_: {
  flake.lib.mkSecretsApp = import ./lib/infisical-secrets.nix;
  flake.lib.mkPaseoPackage = import ./lib/paseo-package.nix;
}
