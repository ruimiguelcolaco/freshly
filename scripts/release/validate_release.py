#!/usr/bin/env python3
import argparse
import pathlib
import plistlib
import re
import sys
from typing import Optional


VERSION_PATTERN = re.compile(r"[0-9]+(?:\.[0-9]+){1,2}(?:-[0-9A-Za-z.-]+)?")
EXPECTED_FEED_URL = (
    "https://github.com/ruimiguelcolaco/freshly/releases/latest/download/appcast.xml"
)


def unique_setting(project: str, name: str) -> str:
    values = set(re.findall(rf"\b{name}\s*=\s*([^;]+);", project))
    if len(values) != 1:
        raise ValueError(f"expected one {name} value, found {sorted(values)}")
    return values.pop().strip('"')


def validate(
    project_path: pathlib.Path,
    version: str,
    tag: Optional[str],
    app: Optional[pathlib.Path],
) -> None:
    project = project_path.read_text(encoding="utf-8")
    marketing_version = unique_setting(project, "MARKETING_VERSION")
    build_version = unique_setting(project, "CURRENT_PROJECT_VERSION")

    if not VERSION_PATTERN.fullmatch(version):
        raise ValueError(f"invalid release version: {version}")
    if marketing_version != version:
        raise ValueError(
            f"release version {version} does not match MARKETING_VERSION {marketing_version}"
        )
    if not build_version.isdecimal() or int(build_version) < 1:
        raise ValueError(f"CURRENT_PROJECT_VERSION must be a positive integer: {build_version}")
    if tag is not None and tag != f"v{version}":
        raise ValueError(f"tag {tag} must be v{version}")

    if app is not None:
        info_path = app / "Contents" / "Info.plist"
        with info_path.open("rb") as info_file:
            info = plistlib.load(info_file)
        if info.get("CFBundleShortVersionString") != version:
            raise ValueError("built app marketing version does not match the release version")
        if str(info.get("CFBundleVersion")) != build_version:
            raise ValueError("built app build number does not match CURRENT_PROJECT_VERSION")
        if info.get("SUFeedURL") != EXPECTED_FEED_URL:
            raise ValueError("built app does not contain the production Sparkle feed URL")
        if not info.get("SUPublicEDKey"):
            raise ValueError("built app does not contain a Sparkle public key")
        if info.get("SUEnableAutomaticChecks") is not True:
            raise ValueError("built app does not enable automatic self-update checks")
        if info.get("SUScheduledCheckInterval") != 86_400:
            raise ValueError("built app does not use the daily self-update interval")
        if info.get("SUAutomaticallyUpdate") is not False:
            raise ValueError("built app must ask before installing self-updates")
        if info.get("SUAllowsAutomaticUpdates") is not False:
            raise ValueError("built app must not offer silent self-updates")
        if info.get("SUShowReleaseNotes") is not True:
            raise ValueError("built app does not enable self-update release notes")


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate a Freshly release version and tag")
    parser.add_argument("--project", default="Freshly.xcodeproj/project.pbxproj", type=pathlib.Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--tag")
    parser.add_argument("--app", type=pathlib.Path)
    arguments = parser.parse_args()
    try:
        validate(arguments.project, arguments.version, arguments.tag, arguments.app)
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        print(f"release validation failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
