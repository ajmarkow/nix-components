# secretty - PTY wrapper that redacts secrets from terminal output
# https://github.com/Suryansh-23/secretty
# Not yet in nixpkgs, so we package it here.
{
  lib,
  buildGoModule,
  fetchFromGitHub,
  ...
}:

buildGoModule (finalAttrs: {
  pname = "secretty";
  version = "0.4.2";

  src = fetchFromGitHub {
    owner = "Suryansh-23";
    repo = "secretty";
    rev = "v${finalAttrs.version}";
    hash = "sha256-W/LxdN7uyN1Uocgthz82wLrJ4227AM9bQDsjSHY6Y7A=";
  };

  vendorHash = "sha256-N3dHiMZgkviBxECHF2hfHkf3TgHN8sS6WOWsW2KOJzA=";

  subPackages = [ "cmd/secretty" ];

  meta = {
    description = "PTY wrapper that redacts secrets from terminal output";
    homepage = "https://github.com/Suryansh-23/secretty";
    license = lib.licenses.mit;
    mainProgram = "secretty";
    platforms = lib.platforms.unix;
  };
})
