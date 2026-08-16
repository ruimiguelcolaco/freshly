#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repository_root"

mode=${1:-all}
derived_data=${FRESHLY_DERIVED_DATA:-/tmp/FreshlyDerivedData}

run_core() {
    swift test --package-path Packages/FreshlyCore
}

run_app() {
    xcodebuild test \
        -project Freshly.xcodeproj \
        -scheme Freshly \
        -destination 'platform=macOS' \
        -derivedDataPath "$derived_data" \
        CODE_SIGNING_ALLOWED=NO
}

run_definitions() {
    verification_directory=$(mktemp -d "${TMPDIR:-/tmp}/freshly-definitions.XXXXXX")
    trap 'rm -rf "$verification_directory"' EXIT HUP INT TERM
    packed_catalog="$verification_directory/definitions-catalog.json"
    swift run --package-path Packages/FreshlyCore validate-definitions \
        Definitions --pack "$packed_catalog"
    if ! cmp -s definitions-catalog.json "$packed_catalog"; then
        echo "definitions-catalog.json is out of date; regenerate it before committing." >&2
        return 1
    fi
}

run_localization() {
    python3 scripts/check_localization.py
}

run_release_tools() {
    PYTHONDONTWRITEBYTECODE=1 python3 scripts/release/validate_release.py \
        --version "$(sed -n 's/.*MARKETING_VERSION = \([^;]*\);/\1/p' Freshly.xcodeproj/project.pbxproj | head -1)"
    PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/release -p 'test_*.py'
}

case "$mode" in
    all)
        run_core
        run_app
        run_definitions
        run_localization
        run_release_tools
        ;;
    core) run_core ;;
    app) run_app ;;
    definitions) run_definitions ;;
    localization) run_localization ;;
    release-tools) run_release_tools ;;
    *)
        echo "Usage: scripts/verify.sh [all|core|app|definitions|localization|release-tools]" >&2
        exit 2
        ;;
esac
