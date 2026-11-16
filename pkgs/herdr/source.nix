# Nix source build of the personal TRAE-enabled Herdr fork. Modeled on
# nixpkgs-unstable's official herdr package (same zig 0.16 vendoring, postPatch
# and completion install), retargeted at PannenetsF/herdr with the fork's own
# source/cargo hashes. Package-set agnostic so it builds on nixpkgs-unstable
# (aarch64-darwin, Linux) and nixos-26.05 (x86_64-darwin, the last release with
# an Intel Darwin stdenv): both provide the zig_0_16.fetchDeps helper, while the
# agent-skills setup hook is vendored locally (./install-agent-skills) because
# the top-level installAgentSkills attr does not exist on 26.05.
{ lib, stdenv, rustPlatform, fetchFromGitHub, zig_0_16, makeSetupHook
, installShellFiles, cctools, xcbuild, pin, }:
let
  installAgentSkills =
    import ./install-agent-skills { inherit lib makeSetupHook; };
in rustPlatform.buildRustPackage (finalAttrs: {
  pname = "herdr";
  # The Cargo package version stays 0.9.5; the personal -traex.N pre-release
  # tag is carried in the Nix version so forks never collide with upstream.
  version = lib.removePrefix "v" pin.tag;

  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = pin.owner;
    repo = pin.repo;
    rev = pin.tag;
    hash = pin.srcHash;
  };

  cargoHash = pin.cargoHash;

  # build.zig.zon is unchanged from upstream 0.9.5, so the vendored zig
  # dependency set (and its hash) is identical to nixpkgs' official recipe.
  zigDeps = zig_0_16.fetchDeps {
    inherit (finalAttrs) pname version;
    src = "${finalAttrs.src}/vendor/libghostty-vt";
    fetchAll = true;
    hash = pin.zigDepsHash;
  };

  nativeBuildInputs = [ zig_0_16 installAgentSkills installShellFiles ]
    ++ lib.optionals stdenv.hostPlatform.isDarwin [ cctools xcbuild ];

  # Same Nix-side fixes as the official package: do not bundle compiler-rt /
  # ubsan on Linux, and replace absolute /usr/bin tool paths on macOS.
  postPatch = lib.optionalString stdenv.hostPlatform.isLinux ''
    substituteInPlace vendor/libghostty-vt/src/build/GhosttyLibVt.zig \
      --replace-fail 'lib.bundle_compiler_rt = true;' 'lib.bundle_compiler_rt = false;' \
      --replace-fail 'lib.bundle_ubsan_rt = true;' 'lib.bundle_ubsan_rt = false;'
  '' + lib.optionalString stdenv.hostPlatform.isDarwin ''
    substituteInPlace vendor/libghostty-vt/pkg/apple-sdk/native_link.zig \
      --replace-fail '"/usr/bin/xcrun"' '"xcrun"'

    substituteInPlace vendor/libghostty-vt/src/build/GhosttyLibVt.zig \
      --replace-fail '"/bin/ln"' '"ln"'

    substituteInPlace vendor/libghostty-vt/src/build/LibtoolStep.zig \
      --replace-fail '/bin/cp ' 'cp ' \
      --replace-fail '/usr/bin/ranlib ' 'ranlib '
  '';

  # Upstream binary tests depend on host process details and are intentionally
  # not run in the Nix build (same rationale as the official package).
  doCheck = false;

  dontUseZigBuild = true;
  dontUseZigCheck = true;
  dontUseZigInstall = true;

  postConfigure = ''
    export ZIG_GLOBAL_CACHE_DIR=$(mktemp -d)
    cp -rL ${finalAttrs.zigDeps} "$ZIG_GLOBAL_CACHE_DIR/p"
    chmod -R u+w "$ZIG_GLOBAL_CACHE_DIR/p"
  '';

  postInstall =
    lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
      installShellCompletion --cmd herdr \
        --bash <("$out/bin/herdr" completion bash) \
        --fish <("$out/bin/herdr" completion fish) \
        --zsh <("$out/bin/herdr" completion zsh)
    '';

  # The binary reports the Cargo version (0.9.5), not the Nix pre-release
  # version, so the stock versionCheckHook would mismatch. Check the actual
  # version line plus the TRAE CLI surface instead — a version string alone
  # would not prove the personal fork is inside the binary.
  doInstallCheck = stdenv.buildPlatform.canExecute stdenv.hostPlatform;
  installCheckPhase = ''
    runHook preInstallCheck
    "$out/bin/herdr" --version | grep -Eq '^herdr [0-9]+\.[0-9]+\.[0-9]+'
    "$out/bin/herdr" integration install --help | grep -q traex
    "$out/bin/herdr" agent start --help | grep -q traex
    runHook postInstallCheck
  '';

  meta = {
    description =
      "Personal TRAE-enabled Herdr fork: terminal workspace manager for AI coding agents";
    homepage = "https://github.com/${pin.owner}/${pin.repo}";
    license = lib.licenses.asl20;
    mainProgram = "herdr";
    platforms = lib.platforms.unix;
  };
})
