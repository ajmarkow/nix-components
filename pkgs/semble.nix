{ pkgs, lib ? pkgs.lib, uv2nix, pyproject-nix, pyproject-build-systems }:

let
  workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./semble-workspace; };

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

  semble-env = pythonSet.mkVirtualEnv "semble-env" workspace.deps.default;
in
# mkVirtualEnv exposes all venv binaries (python3, pip, etc.) which conflict
# with system packages. Wrap to expose only the semble binary.
pkgs.runCommandNoCC "semble" { meta.mainProgram = "semble"; } ''
  mkdir -p $out/bin
  ln -s ${semble-env}/bin/semble $out/bin/semble
''
