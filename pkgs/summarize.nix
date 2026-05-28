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

  # package.json uses pnpm 10 format for patchedDependencies (path string only),
  # but pnpm-lock.yaml uses pnpm 11 format ({hash, path}). pnpm 11 rejects the
  # mismatch. Fix by reading the lockfile's patchedDependencies and writing them
  # back into package.json so both files use the same format. overrides already
  # match and are left untouched.
  pnpmPatch = ''
    patched=$(${pkgs.yq-go}/bin/yq '.patchedDependencies' pnpm-lock.yaml -o=json)
    ${pkgs.jq}/bin/jq --argjson patched "$patched" \
      '.pnpm.patchedDependencies = $patched' \
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
    pkgs.yq-go
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
