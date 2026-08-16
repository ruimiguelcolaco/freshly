#!/bin/sh
set -eu

if [ "$#" -ne 5 ]; then
    echo "Usage: assemble.sh APP VERSION TAG OUTPUT_DIRECTORY GENERATE_APPCAST" >&2
    exit 2
fi

app=$1
version=$2
tag=$3
output_directory=$4
generate_appcast=$5
repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
epoch=${SOURCE_DATE_EPOCH:-$(git -C "$repository_root" log -1 --format=%ct)}
archive_name="Freshly-$version.zip"

if [ -e "$output_directory" ]; then
    echo "Output directory already exists: $output_directory" >&2
    exit 1
fi
mkdir -p "$output_directory"

python3 "$repository_root/scripts/release/validate_release.py" \
    --project "$repository_root/Freshly.xcodeproj/project.pbxproj" \
    --version "$version" --tag "$tag" --app "$app"
python3 "$repository_root/scripts/release/deterministic_zip.py" \
    "$app" "$output_directory/$archive_name" --epoch "$epoch"
python3 "$repository_root/scripts/release/release_metadata.py" notes \
    --version "$version" "$repository_root/CHANGELOG.md" \
    "$output_directory/Freshly-$version.md"
python3 "$repository_root/scripts/release/release_metadata.py" cask \
    --version "$version" --archive "$output_directory/$archive_name" \
    --output "$output_directory/freshly.rb"

if [ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]; then
    printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | "$generate_appcast" \
        --ed-key-file - \
        --download-url-prefix "https://github.com/ruimiguelcolaco/freshly/releases/download/$tag/" \
        --embed-release-notes --maximum-deltas 0 "$output_directory"
else
    "$generate_appcast" --account com.rux.Freshly \
        --download-url-prefix "https://github.com/ruimiguelcolaco/freshly/releases/download/$tag/" \
        --embed-release-notes --maximum-deltas 0 "$output_directory"
fi
