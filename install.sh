#!/bin/sh
# Installs Finicky Picker. Usage: ./install.sh [--browser "Google Chrome"]
set -e
SRC="$(cd "$(dirname "$0")" && pwd)"

BROWSER=""
[ "$1" = "--browser" ] && BROWSER="$2"
if [ -z "$BROWSER" ]; then
  if [ -d "/Applications/Comet.app" ]; then BROWSER="Comet"; else BROWSER="Google Chrome"; fi
fi

if [ ! -d "/Applications/Finicky.app" ]; then
  echo "Finicky isn't installed. Install it first:  brew install --cask finicky"
  exit 1
fi

"$SRC/build.sh"

CONFIG="$HOME/.finicky.js"
if [ -f "$CONFIG" ] && grep -q "learned:start" "$CONFIG"; then
  echo "Kept your existing $CONFIG (it already has a learned block)."
else
  if [ -f "$CONFIG" ]; then
    cp "$CONFIG" "$CONFIG.bak"
    echo "Backed up your old config to $CONFIG.bak. Copy any rules you want to keep into the new one."
  fi
  sed -e "s|__HOME__|$HOME|" -e "s|__BROWSER__|$BROWSER|" "$SRC/finicky.example.js" > "$CONFIG"
  echo "Wrote $CONFIG for $BROWSER."
fi

open -a Finicky
echo "Done. Open Finicky once and let it be your default browser, then click any link."
