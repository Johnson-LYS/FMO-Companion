#!/usr/bin/env python3

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("ci_pre_xcodebuild.sh")
CLOUD_VARIABLES = (
    "CI_XCODE_CLOUD",
    "CI_XCODEBUILD_ACTION",
    "CI_PRIMARY_REPOSITORY_PATH",
    "CI_BUILD_NUMBER",
    "CI_COMMIT",
)


def run_script(script: Path = SCRIPT, **variables: str) -> subprocess.CompletedProcess[str]:
    environment = os.environ.copy()
    for key in CLOUD_VARIABLES:
        environment.pop(key, None)
    environment.update(variables)
    return subprocess.run(
        ["/bin/sh", str(script)],
        check=False,
        cwd=script.parent,
        env=environment,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )


class PreXcodebuildTests(unittest.TestCase):
    def test_test_without_building_does_not_require_source(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            result = run_script(
                CI_XCODE_CLOUD="TRUE",
                CI_XCODEBUILD_ACTION="test-without-building",
                CI_PRIMARY_REPOSITORY_PATH=str(Path(directory) / "missing-source"),
                CI_BUILD_NUMBER="42",
            )

        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("reuses previously built artifacts", result.stdout)
        self.assertNotIn("Localization validation", result.stdout)

    def test_source_action_fails_before_validation_when_project_is_unavailable(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            scripts = root / "ci_scripts"
            scripts.mkdir()
            isolated_script = scripts / SCRIPT.name
            shutil.copy2(SCRIPT, isolated_script)

            result = run_script(
                isolated_script,
                CI_XCODE_CLOUD="TRUE",
                CI_XCODEBUILD_ACTION="archive",
                CI_PRIMARY_REPOSITORY_PATH=str(root),
                CI_BUILD_NUMBER="42",
            )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("requires source", result.stdout)
        self.assertNotIn("validate_localizations.py", result.stdout)

    def test_unknown_cloud_action_fails_closed(self) -> None:
        result = run_script(
            CI_XCODE_CLOUD="TRUE",
            CI_XCODEBUILD_ACTION="clean",
            CI_BUILD_NUMBER="42",
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Unsupported CI_XCODEBUILD_ACTION: clean", result.stdout)


if __name__ == "__main__":
    unittest.main()
