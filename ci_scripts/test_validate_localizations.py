#!/usr/bin/env python3

from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path

from ci_scripts.validate_localizations import restore_tracked_file


class RestoreTrackedFileTests(unittest.TestCase):
    def test_restores_missing_file_from_current_head(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tracked = root / "FMOc/Resources/Localizable.xcstrings"
            tracked.parent.mkdir(parents=True)
            tracked.write_text('{"sourceLanguage":"en"}\n', encoding="utf-8")

            subprocess.run(["git", "init", "-q"], cwd=root, check=True)
            subprocess.run(["git", "add", tracked.relative_to(root)], cwd=root, check=True)
            subprocess.run(
                [
                    "git",
                    "-c",
                    "user.name=CI Test",
                    "-c",
                    "user.email=ci@example.invalid",
                    "commit",
                    "-qm",
                    "fixture",
                ],
                cwd=root,
                check=True,
            )
            tracked.unlink()

            restore_tracked_file(tracked, repository_root=root)

            self.assertEqual(
                tracked.read_text(encoding="utf-8"),
                '{"sourceLanguage":"en"}\n',
            )

    def test_rejects_missing_untracked_file(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(["git", "init", "-q"], cwd=root, check=True)
            subprocess.run(
                [
                    "git",
                    "-c",
                    "user.name=CI Test",
                    "-c",
                    "user.email=ci@example.invalid",
                    "commit",
                    "--allow-empty",
                    "-qm",
                    "fixture",
                ],
                cwd=root,
                check=True,
            )

            with self.assertRaises(FileNotFoundError):
                restore_tracked_file(root / "missing.xcstrings", repository_root=root)


if __name__ == "__main__":
    unittest.main()
