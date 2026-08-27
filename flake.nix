{
  nixConfig = {
    extra-substituters = [ "https://codex-cli.cachix.org" ];
    extra-trusted-public-keys = [
      "codex-cli.cachix.org-1:1Br3H1hHoRYG22n//cGKJOk3cQXgYobUel6O8DgSing="
    ];
  };

  description = "Reusable Nix modules shared across multiple host configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-parts.url = "github:hercules-ci/flake-parts";
    paseo-skills = {
      url = "github:getpaseo/paseo";
      flake = false;
    };
    superpowers-skills = {
      url = "github:obra/superpowers";
      flake = false;
    };
    obsidian-skills = {
      url = "github:kepano/obsidian-skills";
      flake = false;
    };
    aws-skills = {
      url = "github:zxkane/aws-skills";
      flake = false;
    };
    codex-plugin-cc = {
      url = "github:openai/codex-plugin-cc";
      flake = false;
    };
    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    claude-code-nix.url = "github:sadjow/claude-code-nix";
    claude-code-nix.inputs.nixpkgs.follows = "nixpkgs";
    codex-cli-nix.url = "github:sadjow/codex-cli-nix";
    codex-cli-nix.inputs.nixpkgs.follows = "nixpkgs";
    backlog-md.url = "github:MrLesk/Backlog.md";
    backlog-md.inputs.nixpkgs.follows = "nixpkgs";

    # Determinate Nix, consumed by os-modules/determinate.nix.
    #
    # `github:` rather than the FlakeHub semver URL upstream documents. FlakeHub
    # serves a tarball whose locked `url` Determinate Nix records WITH
    # `?rev=...&revCount=...` query params, while upstream Nix normalizes the
    # same URL without them and then refuses the lock outright:
    #
    #   error: mismatch in field 'url' of input '{... source.tar.gz?rev=...}',
    #   got '{... source.tar.gz}'
    #
    # That breaks any repo locked on a Determinate host and checked in CI on
    # upstream Nix -- which is every host repo here, since the hosts run
    # Determinate and CI uses cachix/install-nix-action. `github:` locks as
    # type/owner/repo/rev with no URL canonicalization, so both agree. The
    # version is still pinned exactly by flake.lock; bump with
    # `nix flake update determinate` like every other input.
    #
    # Deliberately NO `inputs.nixpkgs.follows` here. The nix-darwin module
    # builds no Nix at all (macOS installs come from Determinate's own .pkg),
    # and on NixOS a follows would rebuild Determinate Nix from source instead
    # of substituting it from install.determinate.systems. It also keeps this
    # input clear of the shared nixpkgs pin.
    determinate.url = "github:DeterminateSystems/determinate";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      imports = [
        ./home-modules.nix
        ./os-modules.nix
        ./overlays.nix
        ./per-system.nix
      ];
    };
}
