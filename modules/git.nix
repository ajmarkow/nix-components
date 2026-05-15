{ pkgs, ... }:
let
  signingKey = "B9076853EC110207A2EE0D5D3D19E49D0F3BD0FA";
in
{
  programs.git = {
    enable = true;
    userName = "AJ Markow";
    userEmail = "alexanderjmarkow@gmail.com";
    signing = {
      key = signingKey;
      signByDefault = true;
    };
    extraConfig = {
      gpg.program = "${pkgs.gnupg}/bin/gpg";
      rerere.enabled = true;
      init.defaultBranch = "main";
      pull.rebase = true;
      diff.algorithm = "histogram";
      fetch.prune = true;
      push.autoSetupRemote = true;
      core.pager = "delta";
      interactive.diffFilter = "delta --color-only";
      delta.navigate = true;
      delta.line-numbers = true;
      merge.conflictstyle = "diff3";
    };
  };

  services.gpg-agent = {
    enable = true;
    enableSshSupport = true;
    defaultCacheTtl = 14400;
    maxCacheTtl = 14400;
  };
}
