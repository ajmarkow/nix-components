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

  failedAssertions = cfg: map (a: a.message) (lib.filter (a: !a.assertion) cfg.assertions);

  # A fully specified host. Must produce a working unit and zero assertions.
  good = mkConfig {
    enable = true;
    hostName = "test-host";
    bucket = "test-bucket";
    paths = [ "/home/testuser/documents" ];
    exclude = [ "**/node_modules" ];
  };

  goodFailures = failedAssertions good;

  service = good.systemd.user.services."restic-backups-b2";
  timer = good.systemd.user.timers."restic-backups-b2";

  # Only the repository entry, so the derivation does not gain a store
  # reference to openssh via the PATH= entry that upstream also emits.
  repoEnv = lib.filter (lib.hasPrefix "RESTIC_REPOSITORY=") service.Service.Environment;
in

if goodFailures != [ ] then
  throw "restic module rejected a valid configuration: ${lib.concatStringsSep "; " goodFailures}"
else
  pkgs.runCommand "restic-module-eval" { } ''
    test '${lib.concatStringsSep "," repoEnv}' = 'RESTIC_REPOSITORY=b2:test-bucket:test-host'
    test '${service.Service.EnvironmentFile}' = '/etc/nixos/secrets/restic.env'
    test '${timer.Timer.OnCalendar}' = 'daily'
    touch "$out"
  ''
