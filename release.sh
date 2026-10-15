#!/bin/sh
# Builds a universal Profiley.app and zips it to dist/Profiley.zip for a GitHub release.
set -e
SRC="$(cd "$(dirname "$0")" && pwd)"
rm -rf "$SRC/dist"
"$SRC/build.sh" --universal "$SRC/dist/Profiley.app"
ditto -c -k --keepParent "$SRC/dist/Profiley.app" "$SRC/dist/Profiley.zip"
echo "Built $SRC/dist/Profiley.zip"
