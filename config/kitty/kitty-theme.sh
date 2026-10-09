#!/usr/bin/env bash
# Interactive kitty theme picker.
#
# fzf lists every theme in the kitty-themes submodule; moving the cursor
# applies the highlighted theme to all kitty windows live, Enter keeps
# it, Esc restores the configured colors. Selection is runtime-only —
# the *-theme.auto.conf scheme takes over again on a macOS appearance
# change or kitty restart.
#
# Remote control goes through a fixed unix socket because `kitty @` has
# no controlling tty inside herdr panes (see `listen_on` in kitty.conf).
set -euo pipefail

socket="${KITTY_SOCKET:-/tmp/kitty}"
theme_dir="${KITTY_THEME_DIR:-$HOME/.config/nix-hm/config/kitty/kitty-themes/themes}"
kitty_dir="${KITTY_CONFIG_DIR:-$HOME/.config/kitty}"

if [[ ! -d "$theme_dir" ]]; then
  echo "kitty-theme: theme directory not found: $theme_dir" >&2
  echo "Initialize the submodule:" >&2
  echo "  git -C $HOME/.config/nix-hm submodule update --init config/kitty/kitty-themes" >&2
  exit 1
fi

kc() { kitty @ --to "unix:$socket" "$@" >/dev/null 2>&1; }

if ! kc get-colors; then
  echo "kitty-theme: cannot reach kitty at unix:$socket" >&2
  echo "Ensure kitty.conf sets 'listen_on unix:$socket' and reload the config." >&2
  exit 1
fi

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
