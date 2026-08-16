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
mount_point="/Volumes/Freshly"
read_write_image="$work_directory/Freshly-rw.dmg"
mounted=false

cleanup() {
    if [ "$mounted" = true ]; then
        diskutil eject "$mount_point" >/dev/null 2>&1 || true
    fi
    rm -rf "$work_directory"
}
trap cleanup EXIT HUP INT TERM
mkdir -p "$staging"

if [ -e "$mount_point" ]; then
    echo "A volume named Freshly is already mounted: $mount_point" >&2
    exit 1
fi

ditto "$app" "$staging/Freshly.app"
ln -s /Applications "$staging/Applications"
hdiutil create -quiet -volname Freshly -srcfolder "$staging" \
    -format UDRW "$read_write_image"
diskutil image attach --nobrowse "$read_write_image" >/dev/null
mounted=true

osascript - Freshly <<'APPLESCRIPT'
on run arguments
    set volumeName to item 1 of arguments
    tell application "Finder"
        tell disk volumeName
            open
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            set pathbar visible of container window to false
            set bounds of container window to {120, 120, 760, 480}
            set viewOptions to icon view options of container window
            set arrangement of viewOptions to not arranged
            set icon size of viewOptions to 104
            set text size of viewOptions to 13
            set label position of viewOptions to bottom
            set background color of viewOptions to {65535, 61680, 62708}
            set position of item "Freshly.app" of container window to {180, 190}
            set position of item "Applications" of container window to {460, 190}
            update without registering applications
            delay 1
            close
            open
            update without registering applications
            delay 2
            close
        end tell
    end tell
end run
APPLESCRIPT

sync
diskutil eject "$mount_point" >/dev/null
mounted=false
hdiutil convert -quiet "$read_write_image" -format UDZO -o "$output"
diskutil image info "$output" >/dev/null
