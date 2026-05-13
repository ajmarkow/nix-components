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
    };
  };

  services.gpg-agent = {
    enable = true;
    enableSshSupport = true;
    defaultCacheTtl = 604800;
    maxCacheTtl = 604800;
  };
}
