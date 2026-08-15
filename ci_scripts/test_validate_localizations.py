#!/usr/bin/env python3

from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

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

    def test_restores_from_exact_commit_without_git_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / "FMOc/Resources/Localizable.xcstrings"
            calls = []

            def fetcher(commit_sha: str, relative_path: str) -> bytes:
                calls.append((commit_sha, relative_path))
                return b'{"sourceLanguage":"en"}\n'

            with patch.dict(
                os.environ,
                {"CI_XCODE_CLOUD": "TRUE", "CI_COMMIT": "A" * 40},
                clear=False,
            ):
                restore_tracked_file(
                    target,
                    repository_root=root,
                    remote_fetcher=fetcher,
                )

            self.assertEqual(
                calls,
                [("a" * 40, "FMOc/Resources/Localizable.xcstrings")],
            )
            self.assertEqual(target.read_bytes(), b'{"sourceLanguage":"en"}\n')

    def test_rejects_invalid_remote_commit(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / "FMOc/Resources/Localizable.xcstrings"

            with self.assertRaisesRegex(FileNotFoundError, "40 位 Git 提交哈希"):
                restore_tracked_file(
                    target,
                    repository_root=root,
                    commit_sha="beta",
                    remote_fetcher=lambda _commit, _path: b"unexpected",
                )


if __name__ == "__main__":
    unittest.main()
