#!/bin/sh
# Installs Finicky Picker. Usage: ./install.sh [--browser "Google Chrome"]
set -e
SRC="$(cd "$(dirname "$0")" && pwd)"

"$SRC/build.sh"
[ "$1" = "--browser" ] && defaults write social.topc.finicky-picker browser "$2"

open "$HOME/Applications/Finicky Picker.app"
echo "Done. In the Saved sites window, press \"Make default browser\" and confirm. Then click any link."
