#!/bin/sh
# Installs Profiley. Usage: ./install.sh [--browser "Google Chrome"]
set -e
SRC="$(cd "$(dirname "$0")" && pwd)"

"$SRC/build.sh"
[ "$1" = "--browser" ] && defaults write com.kamalkhatwani.profiley browser "$2"

open "$HOME/Applications/Profiley.app"
echo "Done. In the Saved sites window, press \"Make default browser\" and confirm. Then click any link."
