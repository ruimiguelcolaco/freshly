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

work_directory=$(mktemp -d "${TMPDIR:-/tmp}/freshly-dmg.XXXXXX")
staging="$work_directory/staging"
script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
layout_template="$script_directory/Freshly.DS_Store.b64"

cleanup() {
    rm -rf "$work_directory"
}
trap cleanup EXIT HUP INT TERM
mkdir -p "$staging"

if [ ! -f "$layout_template" ]; then
    echo "DMG layout template does not exist: $layout_template" >&2
    exit 1
fi

ditto "$app" "$staging/Freshly.app"
ln -s /Applications "$staging/Applications"
base64 -D -i "$layout_template" -o "$staging/.DS_Store"
hdiutil create -quiet -volname Freshly -srcfolder "$staging" \
    -format UDZO "$output"
diskutil image info "$output" >/dev/null
