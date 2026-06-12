#!/usr/bin/env bash

if ! pgrep -f "kitty" >/dev/null 2>&1; then
	open -a "/Applications/kitty.app"
else
	# Create a new window, or restart kitty if AppleScript cannot reach it.
	script='tell application "kitty" to create window with default profile'
	! osascript -e "${script}" >/dev/null 2>&1 && {
		while IFS="" read -r pid; do
			kill -15 "${pid}"
		done < <(pgrep -f "kitty")
		open -a "/Applications/kitty.app"
	}
fi
