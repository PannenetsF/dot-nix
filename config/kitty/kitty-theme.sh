#!/usr/bin/env bash
# Interactive kitty theme picker.
#
# fzf lists every theme in the kitty-themes submodule; moving the cursor
# applies the highlighted theme to all kitty windows live, Enter keeps
# it, Esc restores the configured colors. Selection is runtime-only —
# the *-theme.auto.conf scheme takes over again on a macOS appearance
# change or kitty restart.
#
# Remote control needs the kitty instance's unix socket because `kitty @`
# has no controlling tty inside herdr panes. kitty always appends
# "-<pid>" to its socket path and the socket of a herdr pane may be stale
# (the herdr server outlives the kitty it was first launched from), so
# probe the env-provided address and then /tmp/kitty-* newest-first.
set -euo pipefail

theme_dir="${KITTY_THEME_DIR:-$HOME/.config/nix-hm/config/kitty/kitty-themes/themes}"
kitty_dir="${KITTY_CONFIG_DIR:-$HOME/.config/kitty}"

if [[ ! -d "$theme_dir" ]]; then
  echo "kitty-theme: theme directory not found: $theme_dir" >&2
  echo "Initialize the submodule:" >&2
  echo "  git -C $HOME/.config/nix-hm submodule update --init config/kitty/kitty-themes" >&2
  exit 1
fi

# Echo an address kitty @ accepts ("unix:/path") for the first socket
# that answers, trying env hints then the newest /tmp/kitty-* files.
find_socket() {
  local -a candidates=()
  local hint s
  for hint in "${KITTY_LISTEN_ON:-}" "${KITTY_SOCKET:-}"; do
    [[ -n "$hint" ]] || continue
    [[ "$hint" == unix:* ]] || hint="unix:$hint"
    candidates+=("${hint#unix:}")
  done
  while IFS= read -r s; do candidates+=("$s"); done < <(
    ls -t /tmp/kitty-* 2>/dev/null
  )

  for s in "${candidates[@]}"; do
    [[ -S "$s" ]] || continue
    if kitty @ --to "unix:$s" get-colors >/dev/null 2>&1; then
      printf '%s\n' "$s"
      return 0
    fi
  done
  return 1
}

if ! socket="$(find_socket)"; then
  echo "kitty-theme: no reachable kitty control socket" >&2
  echo "Start kitty with remote control enabled (allow_remote_control yes in kitty.conf)." >&2
  exit 1
fi

kc() { kitty @ --to "unix:$socket" "$@" >/dev/null 2>&1; }

# Resolve a list entry to `set-colors` arguments.
apply_pick() {
  case "$1" in
    "[reset]")
      kc set-colors -a --reset
      echo "kitty-theme: reset to configured colors"
      ;;
    "[auto] dark")
      kc set-colors -a -c "$kitty_dir/dark-theme.auto.conf"
      echo "kitty-theme: dark-theme.auto.conf"
      ;;
    "[auto] light")
      kc set-colors -a -c "$kitty_dir/light-theme.auto.conf"
      echo "kitty-theme: light-theme.auto.conf"
      ;;
    *)
      kc set-colors -a -c "$theme_dir/$1.conf"
      echo "kitty-theme: $1"
      ;;
  esac
}

# fzf --preview runs on every cursor move; the preview window itself is
# hidden, its only job is to fire set-colors for the highlighted row.
preview_sh="$(mktemp)"
cat >"$preview_sh" <<EOF
#!/bin/sh
case "\$1" in
  "[reset]")        set -- --reset ;;
  "[auto] dark")    set -- -c "$kitty_dir/dark-theme.auto.conf" ;;
  "[auto] light")   set -- -c "$kitty_dir/light-theme.auto.conf" ;;
  *)                set -- -c "$theme_dir/\$1.conf" ;;
esac
kitty @ --to "unix:$socket" set-colors -a "\$@" >/dev/null 2>&1
EOF
trap 'rm -f "$preview_sh"' EXIT

pick="$(
  {
    printf '[reset]\n[auto] dark\n[auto] light\n'
    find "$theme_dir" -maxdepth 1 -name '*.conf' -print \
      | sed 's|.*/||; s|\.conf$||' | sort
  } | fzf \
      --prompt='kitty theme > ' \
      --header='Enter: apply   Esc: cancel & restore   type to filter' \
      --preview="sh '$preview_sh' {}" \
      --preview-window=hidden
)" || true

if [[ -z "$pick" ]]; then
  kc set-colors -a --reset
  echo "kitty-theme: canceled, restored configured colors"
  exit 0
fi

apply_pick "$pick"
