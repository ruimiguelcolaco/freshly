#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
    echo "Usage: create_dmg.sh APP OUTPUT_DMG" >&2
    exit 2
fi

app=$1
output=$2

if [ ! -d "$app" ]; then
    echo "App bundle does not exist: $app" >&2
    exit 1
fi
if [ -e "$output" ]; then
    echo "DMG already exists: $output" >&2
    exit 1
fi

staging=$(mktemp -d "${TMPDIR:-/tmp}/freshly-dmg.XXXXXX")
trap 'rm -rf "$staging"' EXIT HUP INT TERM

ditto "$app" "$staging/Freshly.app"
ln -s /Applications "$staging/Applications"
hdiutil create -quiet -volname Freshly -srcfolder "$staging" \
    -format UDZO "$output"
diskutil image info "$output" >/dev/null
