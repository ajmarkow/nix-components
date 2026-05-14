{ pkgs, ... }:
let
  signingKey = "0E96371A9739318ADA6E6F1ADF9CCC102CBF66CB";
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
