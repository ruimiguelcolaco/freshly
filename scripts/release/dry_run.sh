#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
version=${1:-$(sed -n 's/.*MARKETING_VERSION = \([^;]*\);/\1/p' "$repository_root/Freshly.xcodeproj/project.pbxproj" | head -1)}
work_directory=$(mktemp -d "${TMPDIR:-/tmp}/freshly-release.XXXXXX")
trap 'rm -rf "$work_directory"' EXIT HUP INT TERM
source_packages="$work_directory/SourcePackages"
archive_path="$work_directory/Freshly.xcarchive"

xcodebuild archive -project "$repository_root/Freshly.xcodeproj" \
    -scheme Freshly -archivePath "$archive_path" \
    -derivedDataPath "$work_directory/DerivedData" \
    -clonedSourcePackagesDirPath "$source_packages" \
    CODE_SIGNING_ALLOWED=NO

generate_appcast="$source_packages/artifacts/sparkle/Sparkle/bin/generate_appcast"
app="$archive_path/Products/Applications/Freshly.app"
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(git -C "$repository_root" log -1 --format=%ct)} \
    "$repository_root/scripts/release/assemble.sh" \
    "$app" "$version" "v$version" "$work_directory/first" "$generate_appcast"
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(git -C "$repository_root" log -1 --format=%ct)} \
    "$repository_root/scripts/release/assemble.sh" \
    "$app" "$version" "v$version" "$work_directory/second" "$generate_appcast"
cmp "$work_directory/first/Freshly-$version.zip" "$work_directory/second/Freshly-$version.zip"
test -s "$work_directory/first/Freshly-$version.dmg"
(
    cd "$work_directory/first"
    shasum -a 256 -c SHA256SUMS
)

destination=${FRESHLY_RELEASE_OUTPUT:-}
if [ -n "$destination" ]; then
    if [ -e "$destination" ]; then
        echo "Release output already exists: $destination" >&2
        exit 1
    fi
    cp -R "$work_directory/first" "$destination"
fi

echo "Release dry run passed for v$version; archive generation is reproducible."
