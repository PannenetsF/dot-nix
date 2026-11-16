# Prebuilt per-platform release binary of the personal TRAE-enabled Herdr,
# downloaded from the fork's GitHub Release. Assets are bare, uncompressed
# executables named herdr-<os>-<arch>; Linux assets are musl-static (the release
# workflow asserts "statically linked" and no unresolved C++ runtime symbols),
# so no interpreter patching or dynamic dependencies are involved.
{ lib, stdenv, fetchurl, installShellFiles, pin, system, }:
let assetSpec = pin.releaseAssets.${system};
in stdenv.mkDerivation {
  pname = "herdr";
  version = lib.removePrefix "v" pin.tag;

  src = fetchurl {
    url =
      "https://github.com/${pin.owner}/${pin.repo}/releases/download/${pin.tag}/${assetSpec.asset}";
    hash = assetSpec.hash;
  };

  nativeBuildInputs = [ installShellFiles ];

  # A bare ELF/Mach-O file rather than an archive, so install it directly. The
  # completion and install-check phases run the result and therefore only exist
  # when the build machine can execute the target (native builds); cross builds
  # — the two Linux assets built on a Mac — skip both, exactly like source.nix.
  phases = [ "installPhase" ]
    ++ lib.optionals (stdenv.buildPlatform.canExecute stdenv.hostPlatform) [
      "completionPhase"
      "installCheckPhase"
    ];

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/herdr"
    runHook postInstall
  '';

  completionPhase = ''
    installShellCompletion --cmd herdr \
      --bash <("$out/bin/herdr" completion bash) \
      --fish <("$out/bin/herdr" completion fish) \
      --zsh <("$out/bin/herdr" completion zsh)
  '';

  # Mirror source.nix: prove both version identity and the TRAE CLI surface;
  # a version string alone would not prove the personal fork is in the binary.
  installCheckPhase = ''
    runHook preInstallCheck
    "$out/bin/herdr" --version | grep -Eq '^herdr [0-9]+\.[0-9]+\.[0-9]+'
    "$out/bin/herdr" integration install --help | grep -q traex
    "$out/bin/herdr" agent start --help | grep -q traex
    runHook postInstallCheck
  '';

  meta = {
    description = "Personal TRAE-enabled Herdr fork (prebuilt release binary)";
    homepage = "https://github.com/${pin.owner}/${pin.repo}";
    license = lib.licenses.asl20;
    mainProgram = "herdr";
    # This derivation fetches the asset for its own Nix system only.
    platforms = [ system ];
  };
}
