#! /bin/bash 
FILE_LOCK=$HOME/pf-init

PIP_EXTRA=""
[ -n "$PIP_POSTFIX" ] && PIP_EXTRA="$PIP_EXTRA $PIP_POSTFIX"
PIP_EXTRA="$PIP_EXTRA --break-system-packages"

if [ -f $FILE_LOCK ]; then 
	echo All py packages are installed yet.
else 
	pwd
	env | grep PATH
	pip3 install ruff ty jedi-language-server pynvim $PIP_EXTRA
	mkdir -p $HOME/.config
	git clone https://github.com/PannenetsF/dot-nvim.git $HOME/.config/nvim
    nvim --headless -c 'Lazy' -c 'qa'
    nvim --headless -c 'TSUpdateSync' -c 'qa'
	echo hello >> $FILE_LOCK
fi

