{ pkgs, lib ? pkgs.lib, ... }:

pkgs.stdenv.mkDerivation (finalAttrs: {
  pname = "summarize";
  version = "0.15.2";

  src = pkgs.fetchFromGitHub {
    owner = "steipete";
    repo = "summarize";
    rev = "0e7a31d0ec95da95a98e6757dca3d6e0e218f230";
    hash = "sha256-5xAwiPCj3exl23b1opRrJy2WxnjqRR7RMjBkIOXyRPA=";
  };

  # package.json lists overrides/patchedDependencies that conflict with the
  # lockfile; strip them from package.json only so pnpm accepts frozen install.
  # Leaving pnpm-lock.yaml intact ensures all patched packages are fetched.
  pnpmPatch = ''
    ${pkgs.jq}/bin/jq 'del(.pnpm.overrides) | del(.pnpm.patchedDependencies)' \
      package.json > package.json.tmp && mv package.json.tmp package.json
  '';

  pnpmDeps = pkgs.fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    prePnpmInstall = finalAttrs.pnpmPatch;
    fetcherVersion = 3;
    hash = "";
  };

  postPatch = finalAttrs.pnpmPatch;

  nativeBuildInputs = [
    pkgs.nodejs
    pkgs.pnpm
    pkgs.pnpmConfigHook
    pkgs.makeWrapper
    pkgs.jq
  ];

  buildPhase = ''
    pnpm build
  '';

  installPhase = ''
    mkdir -p $out/lib/summarize $out/bin
    cp -r . $out/lib/summarize/

    makeWrapper ${pkgs.nodejs}/bin/node $out/bin/summarize \
      --add-flags "$out/lib/summarize/dist/cli.js"
    ln -s $out/bin/summarize $out/bin/summarizer
  '';

  meta = {
    description = "Link → clean text → summary";
    homepage = "https://summarize.sh";
    mainProgram = "summarize";
  };
})
