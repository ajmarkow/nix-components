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

  # pnpm 11 rejects frozen install when package.json and pnpm-lock.yaml disagree
  # on overrides/patchedDependencies. Strip both fields from both files so they
  # trivially agree. Also remove (patch_hash=...) suffixes from snapshot keys in
  # the lockfile — without patchedDependencies, pnpm can't resolve patch-keyed
  # snapshots and silently skips fetching them, causing offline install failures.
  pnpmPatch = ''
    ${pkgs.jq}/bin/jq 'del(.pnpm.overrides) | del(.pnpm.patchedDependencies)' \
      package.json > package.json.tmp && mv package.json.tmp package.json
    ${pkgs.yq-go}/bin/yq 'del(.overrides) | del(.patchedDependencies)' \
      pnpm-lock.yaml > pnpm-lock.yaml.tmp && mv pnpm-lock.yaml.tmp pnpm-lock.yaml
    ${pkgs.gnused}/bin/sed -i 's/(patch_hash=[^)]*)//g' pnpm-lock.yaml
  '';

  pnpmDeps = pkgs.fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    prePnpmInstall = finalAttrs.pnpmPatch;
    fetcherVersion = 3;
    hash = "sha256-aULoD2FdLRpTRFbecs+Ihe2vceJQ7SbbInrU3VHH6aM=";
  };

  postPatch = finalAttrs.pnpmPatch;

  nativeBuildInputs = [
    pkgs.nodejs
    pkgs.pnpm
    pkgs.pnpmConfigHook
    pkgs.makeWrapper
    pkgs.jq
    pkgs.yq-go
    pkgs.gnused
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
