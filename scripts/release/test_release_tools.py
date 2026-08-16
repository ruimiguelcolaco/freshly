import os
import pathlib
import plistlib
import tempfile
import unittest
import zipfile

from deterministic_zip import create_archive
from release_metadata import cask, checksums, release_notes
from validate_release import validate


class ReleaseToolTests(unittest.TestCase):
    def test_release_validation_checks_project_tag_and_built_app(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = pathlib.Path(temporary_directory)
            project = root / "project.pbxproj"
            project.write_text(
                "MARKETING_VERSION = 1.2.3;\nCURRENT_PROJECT_VERSION = 42;\n",
                encoding="utf-8",
            )
            app = root / "Freshly.app"
            info = app / "Contents" / "Info.plist"
            info.parent.mkdir(parents=True)
            with info.open("wb") as info_file:
                plistlib.dump(
                    {
                        "CFBundleShortVersionString": "1.2.3",
                        "CFBundleVersion": "42",
                        "SUFeedURL": (
                            "https://github.com/ruimiguelcolaco/freshly/"
                            "releases/latest/download/appcast.xml"
                        ),
                        "SUPublicEDKey": "public-key",
                        "SUEnableAutomaticChecks": True,
                        "SUScheduledCheckInterval": 86_400,
                        "SUAutomaticallyUpdate": False,
                        "SUAllowsAutomaticUpdates": False,
                        "SUShowReleaseNotes": True,
                    },
                    info_file,
                )

            validate(project, "1.2.3", "v1.2.3", app)
            with self.assertRaisesRegex(ValueError, "must be v1.2.3"):
                validate(project, "1.2.3", "1.2.3", app)

            with info.open("wb") as info_file:
                plistlib.dump(
                    {
                        "CFBundleShortVersionString": "1.2.3",
                        "CFBundleVersion": "42",
                    },
                    info_file,
                )
            with self.assertRaisesRegex(ValueError, "production Sparkle feed URL"):
                validate(project, "1.2.3", "v1.2.3", app)

    def test_release_validation_accepts_a_matching_beta_version(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            project = pathlib.Path(temporary_directory) / "project.pbxproj"
            project.write_text(
                "MARKETING_VERSION = 1.0-beta.1;\n"
                "CURRENT_PROJECT_VERSION = 2;\n",
                encoding="utf-8",
            )

            validate(project, "1.0-beta.1", "v1.0-beta.1", None)

    def test_archive_is_reproducible_and_preserves_symlinks_and_modes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = pathlib.Path(temporary_directory)
            app = root / "Freshly.app"
            executable = app / "Contents" / "MacOS" / "Freshly"
            executable.parent.mkdir(parents=True)
            executable.write_text("binary", encoding="utf-8")
            executable.chmod(0o755)
            os.symlink("Versions/Current", app / "Framework")
            first = root / "first.zip"
            second = root / "second.zip"

            create_archive(app, first, 1_800_000_000)
            create_archive(app, second, 1_800_000_000)

            self.assertEqual(first.read_bytes(), second.read_bytes())
            with zipfile.ZipFile(first) as archive:
                executable_info = archive.getinfo("Freshly.app/Contents/MacOS/Freshly")
                link_info = archive.getinfo("Freshly.app/Framework")
                self.assertEqual((executable_info.external_attr >> 16) & 0o777, 0o755)
                self.assertTrue((link_info.external_attr >> 16) & 0o120000)

    def test_metadata_uses_versioned_notes_and_archive_digest(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            archive = pathlib.Path(temporary_directory) / "Freshly-1.0.zip"
            archive.write_bytes(b"release")
            notes = release_notes(
                "# Changelog\n\n## [Unreleased]\n\n- Future\n\n"
                "## [1.0] - 2026-08-16\n\n### Added\n\n- Feature\n\n"
                "## [0.9]\n",
                "1.0",
            )
            generated_cask = cask("1.0", archive)

            self.assertEqual(notes, "### Added\n\n- Feature\n")
            self.assertIn('version "1.0"', generated_cask)
            self.assertIn(
                'sha256 "a4d451ec23463726f72c43d64c710968f6b602cd653b4de8adee1b556240a829"',
                generated_cask,
            )

    def test_metadata_falls_back_to_unreleased_notes_before_version_cut(self) -> None:
        notes = release_notes(
            "# Changelog\n\n## [Unreleased]\n\n### Fixed\n\n- Preview fix\n",
            "1.0",
        )
        self.assertEqual(notes, "### Fixed\n\n- Preview fix\n")

    def test_metadata_rejects_an_empty_release_section(self) -> None:
        with self.assertRaisesRegex(ValueError, "changelog section is empty"):
            release_notes(
                "# Changelog\n\n## [Unreleased]\n\n- Future\n\n## [1.0]\n\n",
                "1.0",
            )

    def test_checksums_are_sorted_and_use_basenames(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = pathlib.Path(temporary_directory)
            archive = root / "Freshly-1.0.zip"
            disk_image = root / "Freshly-1.0.dmg"
            archive.write_bytes(b"zip")
            disk_image.write_bytes(b"dmg")

            generated = checksums([archive, disk_image])

            self.assertEqual(
                generated,
                "00cbbd0ddbda2762798f7009838ed34ca1f12b93965813c7df22943bc62166d1"
                "  Freshly-1.0.dmg\n"
                "4a70fe9aa6436e02c2dea340fbd1e352e4ef2d8ce6ca52ad25d4b95471fc8bf2"
                "  Freshly-1.0.zip\n",
            )


if __name__ == "__main__":
    unittest.main()
