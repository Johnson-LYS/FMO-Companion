#!/usr/bin/env python3
"""Isolated end-to-end tests for the FMO identity issuer."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import time
import unittest


SCRIPT = Path(__file__).with_name("fmo_identity_issuer.py").resolve()
SPEC = importlib.util.spec_from_file_location("fmo_identity_issuer", SCRIPT)
assert SPEC and SPEC.loader
issuer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(issuer)


class IdentityIssuerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="fmo-identity-issuer-test-")
        self.base = Path(self.temporary.name)
        self.pki = self.base / "pki-test"
        self.pki.mkdir(mode=0o700)
        self.output = self.base / "output"
        self.registry = self.base / "registry.sqlite3"
        self.now = int(time.time())
        self.root_seed = issuer.b64url_encode(bytes(range(32)))
        self.intermediate_seed = issuer.b64url_encode(bytes(range(1, 33)))
        self.root_public = issuer.crypto("derive", privateKey=self.root_seed)["publicKey"]
        self.intermediate_public = issuer.crypto("derive", privateKey=self.intermediate_seed)["publicKey"]
        self.root, self.intermediate = self._create_ca()
        self.root_fingerprint = issuer.fingerprint(issuer.root_tbs(self.root))

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def _create_ca(self) -> tuple[dict, dict]:
        root = {
            "sn": 9001,
            "type": "rootCA",
            "issuer": {"name": "Test Root", "email": "test@example.com"},
            "subject": {"name": "Test Root", "publicKey": self.root_public},
            "extensions": {"isCA": True, "pathLen": 1, "crl": "", "license": "", "keyId": "test-root"},
            "iat": self.now - 60,
            "exp": self.now + 864000,
            "signatureAlgorithm": "Ed25519",
            "signature": "",
        }
        root["signature"] = issuer.crypto(
            "sign", privateKey=self.root_seed, message=issuer.b64url_encode(issuer.root_tbs(root))
        )["signature"]
        intermediate = {
            "sn": 9002,
            "type": "intermediateCA",
            "issuer": {"sn": 9001, "name": "Test Root", "publicKey": self.root_public},
            "subject": {
                "name": "Test Intermediate", "email": "test@example.com",
                "publicKey": self.intermediate_public,
            },
            "extensions": {
                "isCA": True, "pathLen": 0, "keyId": "test-intermediate", "crl": "", "license": "",
                "uidRange": {"start": 100, "end": 199}, "issuingCountries": ["CN"],
            },
            "iat": self.now - 60,
            "exp": self.now + 700000,
            "signatureAlgorithm": "Ed25519",
            "signature": "",
        }
        intermediate["signature"] = issuer.crypto(
            "sign", privateKey=self.root_seed,
            message=issuer.b64url_encode(issuer.intermediate_tbs(intermediate)),
        )["signature"]
        key = {
            "format": "fmo-ed25519-private-key", "version": 1,
            "publicKey": self.intermediate_public, "privateKey": self.intermediate_seed,
        }
        for name, value in (
            ("root.cert.json", root), ("intermediate.cert.json", intermediate),
            ("intermediate.key.json", key),
        ):
            path = self.pki / name
            path.write_text(json.dumps(value), encoding="utf-8")
            path.chmod(0o600 if name.endswith("key.json") else 0o644)
        return root, intermediate

    def run_cli(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["python3", str(SCRIPT), *arguments], text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
        )

    def issue(self, public_key: str, label: str) -> subprocess.CompletedProcess[str]:
        return self.run_cli(
            "issue", "--callsign", "TEST1", "--public-key", public_key, "--label", label,
            "--valid-days", "1", "--pki-dir", str(self.pki), "--registry", str(self.registry),
            "--output-dir", str(self.output), "--expected-root-fingerprint", self.root_fingerprint,
        )

    def test_issue_verify_and_duplicate_fail_closed(self) -> None:
        user_seed = issuer.b64url_encode(bytes(range(2, 34)))
        user_public = issuer.crypto("derive", privateKey=user_seed)["publicKey"]
        first = self.issue(user_public, "ios-test")
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertIn("Issued UID: 100", first.stdout)
        bundle = self.output / "FMOCompanion-TEST1-100.identity.json"
        verified = self.run_cli(
            "verify", "--bundle", str(bundle), "--expected-root-fingerprint", self.root_fingerprint,
        )
        self.assertEqual(verified.returncode, 0, verified.stderr)
        self.assertIn("Identity bundle is valid.", verified.stdout)
        registered = self.run_cli(
            "register", "--bundle", str(bundle), "--label", "ios-test",
            "--registry", str(self.registry), "--expected-root-fingerprint", self.root_fingerprint,
        )
        self.assertEqual(registered.returncode, 0, registered.stderr)
        self.assertIn("Registered existing identity", registered.stdout)
        duplicate = self.issue(user_public, "ios-test")
        self.assertEqual(duplicate.returncode, 1)
        self.assertIn("already registered", duplicate.stderr)
        self.assertTrue(bundle.exists(), "duplicate attempt must not delete the existing bundle")

    def test_concurrent_allocation_produces_distinct_uids(self) -> None:
        public_keys = [
            issuer.crypto("derive", privateKey=issuer.b64url_encode(bytes(range(offset, offset + 32))))["publicKey"]
            for offset in (3, 4)
        ]
        commands = []
        for index, public_key in enumerate(public_keys):
            command = [
                "python3", str(SCRIPT), "issue", "--callsign", "TEST1", "--public-key", public_key,
                "--label", f"ios-concurrent-{index}", "--valid-days", "1", "--pki-dir", str(self.pki),
                "--registry", str(self.registry), "--output-dir", str(self.output),
                "--expected-root-fingerprint", self.root_fingerprint,
            ]
            commands.append(subprocess.Popen(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE))
        results = [process.communicate(timeout=30) + (process.returncode,) for process in commands]
        for stdout, stderr, returncode in results:
            self.assertEqual(returncode, 0, stderr)
            self.assertIn("Issued UID:", stdout)
        bundles = sorted(path.name for path in self.output.glob("*.identity.json"))
        self.assertEqual(bundles, ["FMOCompanion-TEST1-100.identity.json", "FMOCompanion-TEST1-101.identity.json"])


if __name__ == "__main__":
    unittest.main()
