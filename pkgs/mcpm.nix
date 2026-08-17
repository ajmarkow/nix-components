{ pkgs, lib ? pkgs.lib, uv2nix, pyproject-nix, pyproject-build-systems }:

# Built from mcpm's own PyPI metadata via uv2nix rather than from the upstream
# mcpm.sh flake. That flake hand-maintains propagatedBuildInputs and omits
# several declared dependencies (tomli, tomli-w, rich-click, inquirerpy,
# rich-gradient, jsonschema, fastmcp), so `mcpm` died on ModuleNotFoundError at
# runtime. uv resolves the full set from pyproject.toml, so there is no list to
# keep in sync here.
let
  workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./mcpm-workspace; };

  overlay = workspace.mkPyprojectOverlay {
    sourcePreference = "wheel";
  };

  python = pkgs.python3;

  pythonSet = (pkgs.callPackage pyproject-nix.build.packages {
    inherit python;
  }).overrideScope (
    lib.composeManyExtensions [
      pyproject-build-systems.overlays.wheel
      overlay
    ]
  );

  mcpm-env = pythonSet.mkVirtualEnv "mcpm-env" workspace.deps.default;
in
# mkVirtualEnv exposes all venv binaries (python3, pip, etc.) which conflict
# with system packages. Wrap to expose only the mcpm binary.
pkgs.runCommand "mcpm" { meta.mainProgram = "mcpm"; } ''
  mkdir -p $out/bin
  ln -s ${mcpm-env}/bin/mcpm $out/bin/mcpm
''
