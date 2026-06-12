#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

make_stub_bin() {
  local bin_dir="$1"

  cat >"${bin_dir}/uname" <<'SH'
#!/usr/bin/env bash
case "$1" in
  -s) printf '%s\n' "${TEST_UNAME_S}" ;;
  -m) printf '%s\n' "${TEST_UNAME_M}" ;;
  *) exit 1 ;;
esac
SH

  cat >"${bin_dir}/nix" <<'SH'
#!/usr/bin/env bash
printf '%q ' "$@" >>"${NIX_STUB_LOG}"
printf '\n' >>"${NIX_STUB_LOG}"
exit 0
SH

  cat >"${bin_dir}/sudo" <<'SH'
#!/usr/bin/env bash
printf 'sudo ' >>"${NIX_STUB_LOG}"
printf '%q ' "$@" >>"${NIX_STUB_LOG}"
printf '\n' >>"${NIX_STUB_LOG}"
exit 0
SH

  cat >"${bin_dir}/launchctl" <<'SH'
#!/usr/bin/env bash
exit 1
SH

  cat >"${bin_dir}/git" <<'SH'
#!/usr/bin/env bash
if [[ "$*" == *"status --porcelain"* ]]; then
  exit 0
fi
if [[ "$*" == *"diff --quiet"* ]]; then
  exit 0
fi
exit 0
SH

  cat >"${bin_dir}/curl" <<'SH'
#!/usr/bin/env bash
exit 0
SH

  cat >"${bin_dir}/apt-get" <<'SH'
#!/usr/bin/env bash
exit 0
SH

  cat >"${bin_dir}/id" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "-u" ]]; then
  printf '%s\n' "${TEST_ID_U:-0}"
  exit 0
fi
exit 1
SH

  cat >"${bin_dir}/whoami" <<'SH'
#!/usr/bin/env bash
printf 'testuser\n'
SH

  chmod +x "${bin_dir}"/*
}

run_init_for() {
  local os="$1"
  local arch="$2"
  local uid="${3:-0}"
  local tmp
  tmp="$(mktemp -d)"

  mkdir -p "${tmp}/bin" "${tmp}/home/.nix-profile/etc/profile.d"
  : >"${tmp}/home/.nix-profile/etc/profile.d/nix.sh"
  make_stub_bin "${tmp}/bin"

  TEST_UNAME_S="$os" \
  TEST_UNAME_M="$arch" \
  TEST_ID_U="$uid" \
  NIX_STUB_LOG="${tmp}/nix.log" \
  PATH="${tmp}/bin:${PATH}" \
  HOME="${tmp}/home" \
  bash "${repo_root}/init.sh" >/dev/null

  cat "${tmp}/nix.log"
  rm -rf "${tmp}"
}

darwin_log="$(run_init_for Darwin arm64 501)"
if [[ "$darwin_log" != *"sudo env"* ]]; then
  echo "expected Darwin init to run darwin-rebuild through sudo env" >&2
  echo "$darwin_log" >&2
  exit 1
fi
if [[ "$darwin_log" != *"HOME="*"/home"* || "$darwin_log" != *"USER=testuser"* ]]; then
  echo "expected Darwin sudo env to preserve original HOME and USER" >&2
  echo "$darwin_log" >&2
  exit 1
fi
if [[ "$darwin_log" != *"#darwin-rebuild"* ]]; then
  echo "expected Darwin init to run the local darwin-rebuild app" >&2
  echo "$darwin_log" >&2
  exit 1
fi
if [[ "$darwin_log" != *"#aarch64-darwin"* ]]; then
  echo "expected Darwin init to target aarch64-darwin" >&2
  echo "$darwin_log" >&2
  exit 1
fi

linux_log="$(run_init_for Linux aarch64)"
if [[ "$linux_log" != *"nixpkgs#home-manager"* ]]; then
  echo "expected Linux init to keep using home-manager" >&2
  echo "$linux_log" >&2
  exit 1
fi
if [[ "$linux_log" != *"#aarch64-linux"* ]]; then
  echo "expected Linux init to target aarch64-linux" >&2
  echo "$linux_log" >&2
  exit 1
fi
