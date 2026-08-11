#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config="${repo_root}/config/alacritty/alacritty.toml"
kitty_theme="${repo_root}/config/kitty/light-theme.auto.conf"

if [[ ! -f "$config" ]]; then
	echo "expected config/alacritty/alacritty.toml to be tracked" >&2
	exit 1
fi

python_bin="${PYTHON:-python3}"
if ! command -v "$python_bin" >/dev/null 2>&1; then
	echo "expected Python 3.11+ with tomllib to validate the Alacritty config" >&2
	exit 1
fi

"$python_bin" - "$config" "$kitty_theme" <<'PY'
import pathlib
import sys
import tomllib

config_path = pathlib.Path(sys.argv[1])
kitty_theme_path = pathlib.Path(sys.argv[2])

with config_path.open("rb") as config_file:
    config = tomllib.load(config_file)

kitty_colors = {}
for raw_line in kitty_theme_path.read_text().splitlines():
    line = raw_line.strip()
    if not line or line.startswith("#"):
        continue
    key, value = line.split(maxsplit=1)
    kitty_colors[key] = value

assert config["general"] == {
    "live_config_reload": True,
    "ipc_socket": True,
}
assert config["env"]["TERM"] == "xterm-256color"
assert config["window"]["decorations"] == "Buttonless"
assert config["window"]["opacity"] == 1.0
assert config["font"]["size"] == 16.0

expected_styles = {
    "normal": "Regular",
    "bold": "Bold",
    "italic": "Italic",
    "bold_italic": "Bold Italic",
}
for face, style in expected_styles.items():
    assert config["font"][face] == {
        "family": "UbuntuMono Nerd Font Mono",
        "style": style,
    }

assert config["scrolling"]["history"] == 2000
assert config["selection"]["save_to_clipboard"] is False
assert config["bell"]["duration"] == 0
assert config["bell"]["command"]["program"] == "/usr/bin/osascript"

assert config["colors"]["primary"] == {
    "background": kitty_colors["background"],
    "foreground": kitty_colors["foreground"],
}
assert config["colors"]["cursor"] == {
    "cursor": kitty_colors["cursor"],
    "text": kitty_colors["cursor_text_color"],
}
assert config["colors"]["selection"] == {
    "background": kitty_colors["selection_background"],
    "text": kitty_colors["selection_foreground"],
}

color_names = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"]
assert config["colors"]["normal"] == {
    name: kitty_colors[f"color{index}"] for index, name in enumerate(color_names)
}
assert config["colors"]["bright"] == {
    name: kitty_colors[f"color{index + 8}"] for index, name in enumerate(color_names)
}

bindings = {
    (binding["mods"], binding["key"]): binding["action"]
    for binding in config["keyboard"]["bindings"]
}
for index in range(1, 9):
    assert bindings[("Control|Shift", str(index))] == f"SelectTab{index}"
PY
