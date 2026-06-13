#! /bin/bash 
FILE_LOCK=$HOME/pf-init

PIP_EXTRA=""
[ -n "$PIP_POSTFIX" ] && PIP_EXTRA="$PIP_EXTRA $PIP_POSTFIX"
PIP_EXTRA="$PIP_EXTRA --break-system-packages"

sync_config_repo() {
	local name="$1"
	local repo_url="$2"
	local dest="$3"
	local status

	mkdir -p "$(dirname "$dest")"
	if [ ! -e "$dest" ]; then
		git clone "$repo_url" "$dest"
		return
	fi

	if [ ! -d "$dest/.git" ]; then
		echo "[install-linux-server.sh] WARNING: $name exists but is not a git repo, skipping pull: $dest" >&2
		return
	fi

	if ! git -C "$dest" diff --quiet || ! git -C "$dest" diff --cached --quiet; then
		echo "[install-linux-server.sh] WARNING: $name has local changes, skipping git pull: $dest" >&2
		return
	fi

	status="$(git -C "$dest" status --porcelain)"
	if [ -n "$status" ]; then
		echo "[install-linux-server.sh] WARNING: $name has untracked files, skipping git pull: $dest" >&2
		return
	fi

	git -C "$dest" pull --ff-only || echo "[install-linux-server.sh] WARNING: failed to pull $name: $dest" >&2
}

sync_config_repo "nvim config" "https://github.com/PannenetsF/dot-nvim.git" "$HOME/.config/nvim"

if [ -f $FILE_LOCK ]; then 
	echo All py packages are installed yet.
else 
	pwd
	env | grep PATH
	pip3 install ruff ty jedi-language-server pynvim $PIP_EXTRA
    nvim --headless -c 'Lazy' -c 'qa'
    nvim --headless -c 'TSUpdateSync' -c 'qa'
	echo hello >> $FILE_LOCK
fi
