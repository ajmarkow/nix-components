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
in
pythonSet.mkVirtualEnv "semble-env" workspace.deps.default
