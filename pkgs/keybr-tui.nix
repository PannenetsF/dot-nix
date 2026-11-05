# keybr-tui: terminal client for the keybr.com typing engine, from the
# PannenetsF/keybr.com fork (packages/tui workspace). The release tarball is
# the self-contained esbuild bundle (dist/keybr-tui.cjs, no runtime npm deps)
# plus the phonetic model binaries in dist/assets/, which the bundle resolves
# relative to its own path, so both are installed side by side.
#
# Built from the release asset rather than the monorepo: package-lock.json
# has nested chalk@6.0.0 entries (keybr-generators, keybr-logger) without a
# `resolved` URL, so buildNpmPackage's offline install fails with ENOTCACHED.
{ lib, stdenvNoCC, fetchurl, makeWrapper, nodejs_22 }:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "keybr-tui";
  version = "0.1.1";

  # Bump: version + hash (the url is derived from version).
  src = fetchurl {
    url =
      "https://github.com/PannenetsF/keybr.com/releases/download/tui-v${finalAttrs.version}/keybr-tui-${finalAttrs.version}.tgz";
    hash = "sha256-fAZhg4lb/M4LI3TCqxtnvsZBSviQM1LEjYu96JTCfkc=";
  };

  nativeBuildInputs = [ makeWrapper ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/keybr-tui $out/bin
    cp -r dist/. $out/lib/keybr-tui/
    makeWrapper ${nodejs_22}/bin/node $out/bin/keybr-tui \
      --add-flags $out/lib/keybr-tui/keybr-tui.cjs
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    [ "$($out/bin/keybr-tui --version)" = "keybr-tui ${finalAttrs.version}" ]
    $out/bin/keybr-tui --help > /dev/null
    runHook postInstallCheck
  '';

  meta = {
    description = "Terminal UI for the keybr.com touch-typing practice engine";
    homepage = "https://github.com/PannenetsF/keybr.com/tree/main/packages/tui";
    license = lib.licenses.agpl3Only;
    mainProgram = "keybr-tui";
    platforms = lib.platforms.unix;
  };
})
