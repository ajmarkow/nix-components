# Evaluation check for modules/restic.nix.
#
# `nix flake check --no-build` does not instantiate home-manager modules, so
# this builds a throwaway homeConfiguration and forces the values the module is
# responsible for. Linux only -- see per-system.nix.
{
  lib,
  pkgs,
  homeManagerLib,
  resticModule,
}:

let
  baseHome = {
    home = {
      username = "testuser";
      homeDirectory = "/home/testuser";
      stateVersion = "26.05";
    };
  };

  # Forcing the result's .config throws "Failed assertions: ..." whenever any
  # assertion fails -- home-manager's homeManagerConfiguration enforces this
  # unconditionally (moduleChecks in modules/default.nix), regardless of the
  # `check` argument, which only controls _module.check's type-strictness and
  # has no effect here. builtins.tryEval below is what lets the bad-config
  # cases probe that throw without aborting the whole evaluation.
  mkConfig =
    resticBackup:
    (homeManagerLib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        resticModule
        baseHome
        { services.resticBackup = resticBackup; }
      ];
    }).config;

  # A fully specified host. Must produce a working unit; must not throw.
  good = mkConfig {
    enable = true;
    hostName = "test-host";
    bucket = "test-bucket";
    paths = [ "/home/testuser/documents" ];
    exclude = [ "**/node_modules" ];
  };

  service = good.systemd.user.services."restic-backups-b2";
  timer = good.systemd.user.timers."restic-backups-b2";

  # Only the repository entry, so the derivation does not gain a store
  # reference to openssh via the PATH= entry that upstream also emits.
  repoEnv = lib.filter (lib.hasPrefix "RESTIC_REPOSITORY=") service.Service.Environment;

  # Each of these omits exactly one required setting and must be rejected --
  # i.e. forcing .config must throw, which tryEval turns into success = false.
  badCases = {
    missingHostName = {
      enable = true;
      bucket = "test-bucket";
      paths = [ "/home/testuser/documents" ];
    };
    missingBucket = {
      enable = true;
      hostName = "test-host";
      paths = [ "/home/testuser/documents" ];
    };
    missingPaths = {
      enable = true;
      hostName = "test-host";
      bucket = "test-bucket";
    };
  };

  unrejected = lib.attrNames (
    lib.filterAttrs (_: c: (builtins.tryEval (mkConfig c)).success) badCases
  );

  # An unset module must stay inert: no assertion fires (no throw), no units.
  disabledResult = builtins.tryEval (mkConfig {
    enable = false;
  });
  disabledHasUnit =
    disabledResult.success && (disabledResult.value.systemd.user.services ? "restic-backups-b2");
in

if unrejected != [ ] then
  throw "restic module accepted invalid configurations: ${lib.concatStringsSep ", " unrejected}"
else if !disabledResult.success then
  throw "restic module asserted while disabled"
else if disabledHasUnit then
  throw "restic module created restic-backups-b2 while disabled"
else
  pkgs.runCommand "restic-module-eval" { } ''
    test '${lib.concatStringsSep "," repoEnv}' = 'RESTIC_REPOSITORY=b2:test-bucket:test-host'
    test '${service.Service.EnvironmentFile}' = '/etc/nixos/secrets/restic.env'
    test '${timer.Timer.OnCalendar}' = 'daily'
    touch "$out"
  ''
