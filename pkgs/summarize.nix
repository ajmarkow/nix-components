{ pkgs, lib ? pkgs.lib }:

pkgs.stdenv.mkDerivation (finalAttrs: {
  pname = "summarize";
  version = "0.15.2";

  src = pkgs.fetchFromGitHub {
    owner = "steipete";
    repo = "summarize";
    rev = "0e7a31d0ec95da95a98e6757dca3d6e0e218f230";
    hash = "sha256-5xAwiPCj3exl23b1opRrJy2WxnjqRR7RMjBkIOXyRPA=";
  };

  pnpmDeps = pkgs.fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    fetcherVersion = 3;
    hash = "sha256-DltAx3cPQT4DccqH1gOdZGYcP2f4QpxxdhFMizSq9zo=";
  };

  nativeBuildInputs = [
    pkgs.nodejs
    pkgs.pnpmConfigHook
    pkgs.makeWrapper
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
