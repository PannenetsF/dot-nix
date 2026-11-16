# Single source of truth for the personal TRAE-enabled Herdr pin.
#
# Upstream Herdr is herdrdev/herdr; the personal fork PannenetsF/herdr adds the
# reviewed experimental traex/traecli agent integration on top of upstream
# master. Its Cargo version stays 0.9.5, so releases carry personal
# pre-release tags of the form v0.9.5-traex.N (not upstream stable versions).
#
# Two consumption modes, selected per system in ./default.nix:
#   1. published per-platform release binaries (bare, static on Linux musl),
#      keyed by Nix system in releaseAssets;
#   2. a Nix source build (./source.nix), used for systems without a published
#      asset (x86_64-apple-darwin, which the release workflow does not build).
#
# Bump procedure when the release thread (t-0019) publishes a new tag:
#   - move `tag` (and every releaseAssets entry) to the new tag;
#   - refresh srcHash: nix-prefetch-url --unpack the GitHub tag archive and
#     convert with `nix hash to-sri` (this is the unpacked NAR hash, NOT the
#     flat tarball checksum printed in the release notes);
#   - refresh cargoHash by building ./source.nix once and copying the hash Nix
#     reports in the mismatch error (the zig dependency hash only changes when
#     vendor/libghostty-vt/build.zig.zon changes);
#   - fill each released asset's hash in releaseAssets via
#     `nix-prefetch-url --type sha256 <asset URL>` then `nix hash to-sri`
#     (fetchurl hashes the bare file, so the flat release SHA256 converts
#     directly);
#   - sync AGENTS.md and tests/herdr_package_test.sh.
{
  owner = "PannenetsF";
  repo = "herdr";

  # Pinned to the cross-platform GitHub Release coordinated by release thread
  # t-0019 (prerelease). All three release assets and the source archive were
  # independently re-fetched and hash-verified before pinning.
  tag = "v0.9.5-traex.6";

  # NAR hash (SRI) of the unpacked GitHub tag source archive; computed via
  # nix-prefetch-url --unpack on the tag tarball. The release notes' flat
  # tarball SHA256 (52fbee3c…) is a different hash and must not be used here.
  srcHash = "sha256-pQdgpgKTTKN2xOskGO5bJ1DZKDZMIKREvkoqIiOg+D8=";

  # cargoHash covers Cargo.lock/crates.io deps (the cargo vendor staging
  # output). The fork adds signal-hook and toml_edit over upstream 0.9.5, so it
  # differs from nixpkgs' official herdr. The vendored tree is plain source and
  # therefore platform-independent: this one hash serves both the unstable
  # (aarch64-darwin/Linux) and nixos-26.05 (x86_64-darwin) package sets.
  # Cargo.lock is unchanged from v0.9.5-traex.4 through traex.6 (only CI
  # workflow commits landed between them).
  cargoHash = "sha256-hppCIcIEAbefGYz1PgHmGuwCcnsr5iS9WtjTA+gCI2M=";

  # vendor/libghostty-vt/build.zig.zon is unchanged from upstream 0.9.5, so the
  # zig dependency set hash is identical to nixpkgs-unstable's herdr recipe.
  zigDepsHash = "sha256-Cy0DdSvce+fhOFIfxHMQGF2b2j16UkS27UpGbfC42XI=";

  # Per-system published release binaries; systems absent from this map build
  # from source. Asset naming mirrors the upstream release workflow:
  #   herdr-macos-aarch64, herdr-linux-x86_64, herdr-linux-aarch64
  # (bare uncompressed binaries, Linux builds statically linked against musl).
  # x86_64-darwin has no release asset and therefore uses the source build.
  releaseAssets = {
    "aarch64-darwin" = {
      asset = "herdr-macos-aarch64";
      hash = "sha256-ONGmZ53C0XKoMq8DUY6kENINiJKs/zHgVc0UE159wQ8=";
    };
    "x86_64-linux" = {
      asset = "herdr-linux-x86_64";
      hash = "sha256-6joCxSfy4CT9gBLyla9zL43Mxez5BJjRurmLyhYe1+4=";
    };
    "aarch64-linux" = {
      asset = "herdr-linux-aarch64";
      hash = "sha256-rA62xvtbip/1lzTq6dLlgMWDdPDknbQt9pakozHzbxU=";
    };
  };
}
