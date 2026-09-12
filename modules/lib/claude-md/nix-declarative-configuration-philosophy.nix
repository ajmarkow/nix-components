''
  ## Nix & Declarative Configuration Philosophy

  **Always edit the source, never the output.** Generated files, installed packages, and applied configurations should never be modified directly. Changes belong in the declarative source:
  - `.nix` files for system/home-manager configuration
  - `devenv.nix` for development environments
  - Configuration modules for tools and services

  Then regenerate with the appropriate apply command (`home-manager switch`, `nixos-rebuild switch`, `devenv up`, etc.).

  - ❌ `nix-env -i package` → ✅ Add to `devenv.packages` or Nix module
  - ❌ Edit generated config files → ✅ Modify the `.nix` source
  - ❌ Manual `.env` setup → ✅ Define in `devenv.nix`
  - ❌ Imperative `mkdir` or `ln -s` → ✅ Use Nix `home.file` or `home.sessionVariables`
''
