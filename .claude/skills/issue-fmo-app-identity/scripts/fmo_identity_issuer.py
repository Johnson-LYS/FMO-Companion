#!/usr/bin/env python3
"""Issue and verify FMO V4 App identity bundles without storing client private keys."""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import sqlite3
import stat
import subprocess
import sys
import tempfile
import time
from typing import Any


class IssuerError(RuntimeError):
    pass


SCRIPT_DIR = Path(__file__).resolve().parent
CRYPTO_HELPER = SCRIPT_DIR / "fmo_crypto.swift"
DEFAULT_HOME = Path.home() / "Library" / "Application Support" / "FMOClientProbe"


def b64url_decode(value: str, name: str, expected: int | None = None) -> bytes:
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9_-]+", value):
        raise IssuerError(f"{name} must be unpadded Base64URL.")
    try:
        decoded = base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))
    except Exception as exc:
        raise IssuerError(f"Invalid Base64URL in {name}.") from exc
    if expected is not None and len(decoded) != expected:
        raise IssuerError(f"{name} must decode to exactly {expected} bytes.")
    return decoded


def b64url_encode(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).decode("ascii").rstrip("=")


def cbor_head(major: int, value: int) -> bytes:
    if value < 0:
        raise IssuerError("CBOR length/value must be non-negative.")
    prefix = major << 5
    if value < 24:
        return bytes([prefix | value])
    if value <= 0xFF:
        return bytes([prefix | 24, value])
    if value <= 0xFFFF:
        return bytes([prefix | 25]) + value.to_bytes(2, "big")
    if value <= 0xFFFFFFFF:
        return bytes([prefix | 26]) + value.to_bytes(4, "big")
    if value <= 0x7FFFFFFFFFFFFFFF:
        return bytes([prefix | 27]) + value.to_bytes(8, "big")
    raise IssuerError("Integer exceeds signed 64-bit range.")


def cbor(value: Any) -> bytes:
    if isinstance(value, bool):
        return b"\xf5" if value else b"\xf4"
    if isinstance(value, int):
        return cbor_head(0, value) if value >= 0 else cbor_head(1, -1 - value)
    if isinstance(value, bytes):
        return cbor_head(2, len(value)) + value
    if isinstance(value, str):
        encoded = value.encode("utf-8")
        return cbor_head(3, len(encoded)) + encoded
    if isinstance(value, list):
        return cbor_head(4, len(value)) + b"".join(cbor(item) for item in value)
    raise IssuerError(f"Unsupported CBOR value: {type(value).__name__}")


def require_dict(parent: dict[str, Any], name: str) -> dict[str, Any]:
    value = parent.get(name)
    if not isinstance(value, dict):
        raise IssuerError(f"{name} must be an object.")
    return value


def require_int(parent: dict[str, Any], name: str) -> int:
    value = parent.get(name)
    if not isinstance(value, int) or isinstance(value, bool):
        raise IssuerError(f"{name} must be an integer.")
    return value


def require_text(parent: dict[str, Any], name: str, allow_empty: bool = False) -> str:
    value = parent.get(name)
    if not isinstance(value, str) or (not allow_empty and not value.strip()):
        qualifier = "" if allow_empty else " and not empty"
        raise IssuerError(f"{name} must be a string{qualifier}.")
    return value


def root_tbs(cert: dict[str, Any]) -> bytes:
    if cert.get("type") != "rootCA" or cert.get("signatureAlgorithm") != "Ed25519":
        raise IssuerError("Invalid Root certificate type or algorithm.")
    issuer = require_dict(cert, "issuer")
    subject = require_dict(cert, "subject")
    ext = require_dict(cert, "extensions")
    if ext.get("isCA") is not True or require_int(ext, "pathLen") != 1:
        raise IssuerError("Root CA extensions are invalid.")
    values = [
        "FMO", 4, "rootCA", require_int(cert, "sn"),
        require_text(issuer, "name"), require_text(issuer, "email"),
        require_text(subject, "name"), b64url_decode(require_text(subject, "publicKey"), "Root public key", 32),
        True, 1, require_text(ext, "crl", True), require_text(ext, "license", True),
        require_text(ext, "keyId"), require_int(cert, "iat"), require_int(cert, "exp"),
    ]
    if values[4] != values[6]:
        raise IssuerError("Root issuer name does not match subject name.")
    return cbor(values)


def intermediate_tbs(cert: dict[str, Any]) -> bytes:
    if cert.get("type") != "intermediateCA" or cert.get("signatureAlgorithm") != "Ed25519":
        raise IssuerError("Invalid Intermediate certificate type or algorithm.")
    issuer = require_dict(cert, "issuer")
    subject = require_dict(cert, "subject")
    ext = require_dict(cert, "extensions")
    uid_range = require_dict(ext, "uidRange")
    countries = ext.get("issuingCountries")
    if ext.get("isCA") is not True or require_int(ext, "pathLen") != 0:
        raise IssuerError("Intermediate CA extensions are invalid.")
    if not isinstance(countries, list) or any(not isinstance(item, str) for item in countries):
        raise IssuerError("Intermediate issuingCountries must be a string array.")
    normalized_countries = sorted(countries)
    if countries != normalized_countries or any(not re.fullmatch(r"[A-Z]{2}", item) for item in countries):
        raise IssuerError("Intermediate issuingCountries are not normalized.")
    return cbor([
        "FMO", 4, "intermediateCA", require_int(cert, "sn"),
        require_int(issuer, "sn"), require_text(issuer, "name"),
        b64url_decode(require_text(issuer, "publicKey"), "Intermediate issuer public key", 32),
        require_text(subject, "name"), require_text(subject, "email"),
        b64url_decode(require_text(subject, "publicKey"), "Intermediate public key", 32),
        True, 0, require_text(ext, "keyId"), require_text(ext, "crl", True),
        require_text(ext, "license", True), require_int(uid_range, "start"),
        require_int(uid_range, "end"), normalized_countries,
        require_int(cert, "iat"), require_int(cert, "exp"),
    ])


def normalize_callsign(value: str) -> str:
    callsign = value.strip().upper()
    if not callsign or any(ord(char) > 127 or char.isspace() or ord(char) < 32 for char in callsign):
        raise IssuerError("Callsign must contain only non-whitespace ASCII characters.")
    return callsign


def user_tbs(cert: dict[str, Any]) -> bytes:
    if cert.get("type") != "userCert" or cert.get("signatureAlgorithm") != "Ed25519":
        raise IssuerError("Invalid User certificate type or algorithm.")
    subject = require_dict(cert, "subject")
    callsign = normalize_callsign(require_text(subject, "callsign"))
    return cbor([
        "FMO", 4, "userCert", require_int(cert, "issuerSn"), callsign,
        require_int(subject, "uid"),
        b64url_decode(require_text(subject, "publicKey"), "User public key", 32),
        require_int(cert, "iat"), require_int(cert, "exp"),
    ])


def fingerprint(tbs: bytes) -> str:
    return b64url_encode(hashlib.sha256(tbs).digest())


def crypto(action: str, **values: str) -> dict[str, Any]:
    if not CRYPTO_HELPER.is_file():
        raise IssuerError(f"Crypto helper not found: {CRYPTO_HELPER}")
    payload = json.dumps({"action": action, **values}, separators=(",", ":")).encode()
    try:
        process = subprocess.run(
            ["xcrun", "swift", str(CRYPTO_HELPER)], input=payload,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
        )
    except FileNotFoundError as exc:
        raise IssuerError("xcrun/swift is required; install Xcode Command Line Tools.") from exc
    if process.returncode != 0:
        message = process.stderr.decode("utf-8", "replace").strip()
        raise IssuerError(f"CryptoKit operation failed: {message}")
    try:
        result = json.loads(process.stdout)
    except json.JSONDecodeError as exc:
        raise IssuerError("CryptoKit helper returned invalid JSON.") from exc
    if not isinstance(result, dict):
        raise IssuerError("CryptoKit helper returned an invalid result.")
    return result


def verify_signature(public_key: str, message: bytes, signature: str) -> bool:
    b64url_decode(public_key, "public key", 32)
    b64url_decode(signature, "signature", 64)
    return crypto("verify", publicKey=public_key, message=b64url_encode(message), signature=signature).get("valid") is True


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise IssuerError(f"Cannot read valid JSON from {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise IssuerError(f"JSON root must be an object: {path}")
    return value


def resolve_home() -> Path:
    return Path(os.environ.get("FMO_IDENTITY_ISSUER_HOME", DEFAULT_HOME)).expanduser().resolve()


def resolve_pki_dir(argument: str | None) -> Path:
    configured = argument or os.environ.get("FMO_PKI_DIR")
    if configured:
        result = Path(configured).expanduser().resolve()
    else:
        candidates = sorted(path for path in resolve_home().glob("pki-*") if path.is_dir())
        if len(candidates) != 1:
            raise IssuerError("Expected exactly one pki-* directory; pass --pki-dir explicitly.")
        result = candidates[0]
    required = ["root.cert.json", "intermediate.cert.json", "intermediate.key.json"]
    missing = [name for name in required if not (result / name).is_file()]
    if missing:
        raise IssuerError(f"PKI directory is missing: {', '.join(missing)}")
    return result


def resolve_registry(argument: str | None) -> Path:
    configured = argument or os.environ.get("FMO_UID_REGISTRY")
    return Path(configured).expanduser().resolve() if configured else resolve_home() / "uid-registry.sqlite3"


def validate_chain(root: dict[str, Any], intermediate: dict[str, Any], now: int) -> tuple[int, int]:
    root_message = root_tbs(root)
    root_subject = require_dict(root, "subject")
    root_public = require_text(root_subject, "publicKey")
    if not verify_signature(root_public, root_message, require_text(root, "signature")):
        raise IssuerError("Root self-signature is invalid.")
    if not (require_int(root, "iat") <= now < require_int(root, "exp")):
        raise IssuerError("Root certificate is not currently valid.")

    inter_message = intermediate_tbs(intermediate)
    issuer = require_dict(intermediate, "issuer")
    if (require_int(issuer, "sn") != require_int(root, "sn")
            or require_text(issuer, "name") != require_text(root_subject, "name")
            or require_text(issuer, "publicKey") != root_public):
        raise IssuerError("Intermediate issuer fields do not bind to Root.")
    if not verify_signature(root_public, inter_message, require_text(intermediate, "signature")):
        raise IssuerError("Intermediate signature is invalid.")
    inter_iat, inter_exp = require_int(intermediate, "iat"), require_int(intermediate, "exp")
    if not (inter_iat <= now < inter_exp) or inter_exp > require_int(root, "exp"):
        raise IssuerError("Intermediate certificate is not currently valid.")
    uid_range = require_dict(require_dict(intermediate, "extensions"), "uidRange")
    start, end = require_int(uid_range, "start"), require_int(uid_range, "end")
    if start < 0 or end < start:
        raise IssuerError("Intermediate UID range is invalid.")
    return start, end


def load_key(path: Path, expected_public: str) -> str:
    metadata = path.stat()
    if not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != os.getuid() or stat.S_IMODE(metadata.st_mode) & 0o077:
        raise IssuerError("Intermediate key must be an owner-only regular file (mode 0600).")
    key = load_json(path)
    if key.get("format") != "fmo-ed25519-private-key" or key.get("version") != 1:
        raise IssuerError("Unsupported Intermediate key format.")
    seed = require_text(key, "privateKey")
    b64url_decode(seed, "Intermediate private key", 32)
    stored_public = require_text(key, "publicKey")
    b64url_decode(stored_public, "Intermediate key publicKey", 32)
    derived = crypto("derive", privateKey=seed).get("publicKey")
    if derived != stored_public or stored_public != expected_public:
        raise IssuerError("Intermediate private key does not match its certificate.")
    return seed


def connect_registry(path: Path) -> sqlite3.Connection:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    try:
        os.chmod(path.parent, 0o700)
    except OSError as exc:
        raise IssuerError(f"Cannot secure registry directory {path.parent}: {exc}") from exc
    connection = sqlite3.connect(path, timeout=30, isolation_level=None)
    connection.execute("PRAGMA foreign_keys = ON")
    connection.execute("""
        CREATE TABLE IF NOT EXISTS uid_registry (
            uid INTEGER PRIMARY KEY,
            callsign TEXT NOT NULL,
            label TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            revoked_at INTEGER,
            UNIQUE(callsign, label)
        )
    """)
    columns = {row[1] for row in connection.execute("PRAGMA table_info(uid_registry)")}
    additions = {
        "public_key": "TEXT", "cert_fingerprint": "TEXT", "issued_at": "INTEGER",
        "expires_at": "INTEGER", "output_path": "TEXT",
    }
    for name, definition in additions.items():
        if name not in columns:
            connection.execute(f"ALTER TABLE uid_registry ADD COLUMN {name} {definition}")
    os.chmod(path, 0o600)
    return connection


def safe_name(value: str) -> str:
    return "".join(char if char.isascii() and (char.isalnum() or char in "-_") else "_" for char in value)


def command_issue(args: argparse.Namespace) -> int:
    callsign = normalize_callsign(args.callsign)
    public_bytes = b64url_decode(args.public_key, "User public key", 32)
    public_key = b64url_encode(public_bytes)
    label = args.label.strip()
    if not label or len(label) > 120 or any(ord(char) < 32 for char in label):
        raise IssuerError("Label must be 1-120 printable characters.")

    pki_dir = resolve_pki_dir(args.pki_dir)
    root = load_json(pki_dir / "root.cert.json")
    intermediate = load_json(pki_dir / "intermediate.cert.json")
    now = int(time.time())
    uid_start, uid_end = validate_chain(root, intermediate, now)
    root_fingerprint = fingerprint(root_tbs(root))
    if not args.expected_root_fingerprint:
        raise IssuerError("Pass --expected-root-fingerprint or set FMO_EXPECTED_ROOT_FINGERPRINT.")
    if args.expected_root_fingerprint != root_fingerprint:
        raise IssuerError("Configured Root fingerprint does not match the signing PKI.")
    intermediate_public = require_text(require_dict(intermediate, "subject"), "publicKey")
    seed = load_key(pki_dir / "intermediate.key.json", intermediate_public)
    exp = now + args.valid_days * 86400
    if args.valid_days <= 0 or exp > require_int(intermediate, "exp"):
        raise IssuerError("Requested User validity is invalid or exceeds Intermediate expiration.")

    registry_path = resolve_registry(args.registry)
    output_dir = Path(args.output_dir).expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    connection = connect_registry(registry_path)
    output_path: Path | None = None
    temp_path: Path | None = None
    output_created = False
    try:
        connection.execute("BEGIN IMMEDIATE")
        existing = connection.execute(
            "SELECT uid FROM uid_registry WHERE callsign = ? AND label = ?", (callsign, label)
        ).fetchone()
        if existing is not None:
            raise IssuerError(f"Identity label is already registered with UID {existing[0]}.")
        same_key = connection.execute(
            "SELECT uid, callsign, label FROM uid_registry WHERE public_key = ? AND revoked_at IS NULL",
            (public_key,),
        ).fetchone()
        if same_key is not None:
            raise IssuerError(f"Public key is already registered as UID {same_key[0]} ({same_key[1]}/{same_key[2]}).")

        if args.uid is not None:
            uid = args.uid
            collision = connection.execute("SELECT callsign, label FROM uid_registry WHERE uid = ?", (uid,)).fetchone()
            if collision:
                raise IssuerError(f"UID {uid} is already registered to {collision[0]}/{collision[1]}.")
        else:
            highest = connection.execute(
                "SELECT MAX(uid) FROM uid_registry WHERE uid BETWEEN ? AND ?", (uid_start, uid_end)
            ).fetchone()[0]
            uid = uid_start if highest is None else highest + 1
        if uid < uid_start or uid > uid_end:
            raise IssuerError(f"UID {uid} is outside Intermediate range [{uid_start}, {uid_end}].")

        user = {
            "type": "userCert", "issuerSn": require_int(intermediate, "sn"),
            "subject": {"callsign": callsign, "uid": uid, "publicKey": public_key},
            "iat": now, "exp": exp, "signatureAlgorithm": "Ed25519", "signature": "",
        }
        message = user_tbs(user)
        signature = crypto("sign", privateKey=seed, message=b64url_encode(message)).get("signature")
        if not isinstance(signature, str) or not verify_signature(intermediate_public, message, signature):
            raise IssuerError("Generated User signature failed self-verification.")
        user["signature"] = signature
        cert_fingerprint = fingerprint(message)
        user["certFingerprint"] = cert_fingerprint
        bundle = {"rootCert": root, "intermediateCert": intermediate, "userCert": user}

        output_path = output_dir / f"FMOCompanion-{safe_name(callsign)}-{uid}.identity.json"
        if output_path.exists():
            raise IssuerError(f"Output already exists: {output_path}")
        fd, temp_name = tempfile.mkstemp(prefix=f".{output_path.name}.", dir=output_dir)
        temp_path = Path(temp_name)
        try:
            os.fchmod(fd, 0o600)
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                json.dump(bundle, handle, ensure_ascii=False, indent=2, sort_keys=True)
                handle.write("\n")
                handle.flush()
                os.fsync(handle.fileno())
        except Exception:
            try:
                os.close(fd)
            except OSError:
                pass
            raise

        connection.execute(
            """INSERT INTO uid_registry
               (uid, callsign, label, created_at, revoked_at, public_key,
                cert_fingerprint, issued_at, expires_at, output_path)
               VALUES (?, ?, ?, ?, NULL, ?, ?, ?, ?, ?)""",
            (uid, callsign, label, now, public_key, cert_fingerprint, now, exp, str(output_path)),
        )
        os.replace(temp_path, output_path)
        temp_path = None
        output_created = True
        connection.execute("COMMIT")
    except Exception:
        try:
            connection.execute("ROLLBACK")
        except sqlite3.Error:
            pass
        if temp_path is not None:
            temp_path.unlink(missing_ok=True)
        if output_created and output_path is not None and output_path.exists():
            output_path.unlink(missing_ok=True)
        raise
    finally:
        connection.close()

    print(f"Issued UID: {uid}")
    print(f"Certificate fingerprint: {cert_fingerprint}")
    print(f"Root fingerprint: {root_fingerprint}")
    print(f"Identity bundle: {output_path}")
    print(f"UID registry: {registry_path}")
    return 0


def verify_bundle(bundle_path: Path, now: int | None = None) -> dict[str, Any]:
    bundle = load_json(bundle_path)
    root = require_dict(bundle, "rootCert")
    intermediate = require_dict(bundle, "intermediateCert")
    user = require_dict(bundle, "userCert")
    checked_at = int(time.time()) if now is None else now
    uid_start, uid_end = validate_chain(root, intermediate, checked_at)
    if require_int(user, "issuerSn") != require_int(intermediate, "sn"):
        raise IssuerError("User issuerSn does not match Intermediate sn.")
    subject = require_dict(user, "subject")
    uid = require_int(subject, "uid")
    if uid < uid_start or uid > uid_end:
        raise IssuerError("User UID is outside the Intermediate range.")
    if not (require_int(user, "iat") <= checked_at < require_int(user, "exp") <= require_int(intermediate, "exp")):
        raise IssuerError("User certificate is not currently valid.")
    message = user_tbs(user)
    inter_public = require_text(require_dict(intermediate, "subject"), "publicKey")
    if not verify_signature(inter_public, message, require_text(user, "signature")):
        raise IssuerError("User signature is invalid.")
    calculated = fingerprint(message)
    embedded = user.get("certFingerprint")
    if embedded is not None and embedded != calculated:
        raise IssuerError("Embedded User certificate fingerprint is incorrect.")
    return {
        "callsign": normalize_callsign(require_text(subject, "callsign")),
        "uid": uid, "fingerprint": calculated, "expires_at": require_int(user, "exp"),
        "root_fingerprint": fingerprint(root_tbs(root)),
    }


def command_verify(args: argparse.Namespace) -> int:
    path = Path(args.bundle).expanduser().resolve()
    result = verify_bundle(path, args.at)
    if args.expected_root_fingerprint and args.expected_root_fingerprint != result["root_fingerprint"]:
        raise IssuerError("Identity bundle Root fingerprint does not match the expected trust anchor.")
    print("Identity bundle is valid.")
    print(f"Callsign: {result['callsign']}")
    print(f"UID: {result['uid']}")
    print(f"Certificate fingerprint: {result['fingerprint']}")
    print(f"Root fingerprint: {result['root_fingerprint']}")
    print(f"Expires at (Unix): {result['expires_at']}")
    return 0


def command_register(args: argparse.Namespace) -> int:
    bundle_path = Path(args.bundle).expanduser().resolve()
    result = verify_bundle(bundle_path)
    if not args.expected_root_fingerprint:
        raise IssuerError("Pass --expected-root-fingerprint or set FMO_EXPECTED_ROOT_FINGERPRINT.")
    if args.expected_root_fingerprint != result["root_fingerprint"]:
        raise IssuerError("Identity bundle Root fingerprint does not match the expected trust anchor.")
    label = args.label.strip()
    if not label or len(label) > 120 or any(ord(char) < 32 for char in label):
        raise IssuerError("Label must be 1-120 printable characters.")
    bundle = load_json(bundle_path)
    user = require_dict(bundle, "userCert")
    subject = require_dict(user, "subject")
    public_key = require_text(subject, "publicKey")
    callsign, uid = result["callsign"], result["uid"]
    registry_path = resolve_registry(args.registry)
    connection = connect_registry(registry_path)
    try:
        connection.execute("BEGIN IMMEDIATE")
        existing = connection.execute(
            "SELECT callsign, label, public_key FROM uid_registry WHERE uid = ?", (uid,)
        ).fetchone()
        if existing is None:
            label_owner = connection.execute(
                "SELECT uid FROM uid_registry WHERE callsign = ? AND label = ?", (callsign, label)
            ).fetchone()
            if label_owner:
                raise IssuerError(f"Identity label is already registered with UID {label_owner[0]}.")
            connection.execute(
                """INSERT INTO uid_registry
                   (uid, callsign, label, created_at, revoked_at, public_key,
                    cert_fingerprint, issued_at, expires_at, output_path)
                   VALUES (?, ?, ?, ?, NULL, ?, ?, ?, ?, ?)""",
                (uid, callsign, label, require_int(user, "iat"), public_key, result["fingerprint"],
                 require_int(user, "iat"), result["expires_at"], str(bundle_path)),
            )
        else:
            existing_callsign, existing_label, existing_public = existing
            if existing_callsign != callsign or existing_label != label:
                raise IssuerError(
                    f"UID {uid} is already registered as {existing_callsign}/{existing_label}; refusing relabel."
                )
            if existing_public not in (None, public_key):
                raise IssuerError(f"UID {uid} is already bound to a different public key.")
            connection.execute(
                """UPDATE uid_registry SET public_key = ?, cert_fingerprint = ?, issued_at = ?,
                   expires_at = ?, output_path = ? WHERE uid = ?""",
                (public_key, result["fingerprint"], require_int(user, "iat"), result["expires_at"],
                 str(bundle_path), uid),
            )
        connection.execute("COMMIT")
    except Exception:
        try:
            connection.execute("ROLLBACK")
        except sqlite3.Error:
            pass
        raise
    finally:
        connection.close()
    print(f"Registered existing identity: {callsign}/{label} UID {uid}")
    print(f"Certificate fingerprint: {result['fingerprint']}")
    print(f"UID registry: {registry_path}")
    return 0


def command_list(args: argparse.Namespace) -> int:
    registry_path = resolve_registry(args.registry)
    if not registry_path.exists():
        print(f"No registry exists at {registry_path}")
        return 0
    connection = connect_registry(registry_path)
    try:
        rows = connection.execute(
            """SELECT uid, callsign, label, cert_fingerprint, expires_at, revoked_at
               FROM uid_registry ORDER BY uid"""
        ).fetchall()
    finally:
        connection.close()
    print("UID\tCALLSIGN\tLABEL\tFINGERPRINT\tEXPIRES\tSTATUS")
    for uid, callsign, label, cert_fp, expires_at, revoked_at in rows:
        status = "revoked" if revoked_at else "active"
        print(f"{uid}\t{callsign}\t{label}\t{cert_fp or '-'}\t{expires_at or '-'}\t{status}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    issue = subparsers.add_parser("issue", help="allocate a UID and issue an identity bundle")
    issue.add_argument("--callsign", required=True)
    issue.add_argument("--public-key", required=True, help="32-byte Ed25519 public key as unpadded Base64URL")
    issue.add_argument("--label", required=True, help="stable auditable device/application label")
    issue.add_argument("--uid", type=int, help="explicit UID for migration; automatic allocation is preferred")
    issue.add_argument("--valid-days", type=int, default=365)
    issue.add_argument("--pki-dir")
    issue.add_argument("--registry")
    issue.add_argument("--expected-root-fingerprint", default=os.environ.get("FMO_EXPECTED_ROOT_FINGERPRINT"))
    issue.add_argument("--output-dir", default=str(Path.home() / "Downloads"))
    issue.set_defaults(function=command_issue)

    verify = subparsers.add_parser("verify", help="verify a complete identity bundle")
    verify.add_argument("--bundle", required=True)
    verify.add_argument("--at", type=int, help="verification Unix timestamp; defaults to now")
    verify.add_argument("--expected-root-fingerprint", default=os.environ.get("FMO_EXPECTED_ROOT_FINGERPRINT"))
    verify.set_defaults(function=command_verify)

    register = subparsers.add_parser("register", help="verify and import an existing bundle into the UID registry")
    register.add_argument("--bundle", required=True)
    register.add_argument("--label", required=True)
    register.add_argument("--registry")
    register.add_argument("--expected-root-fingerprint", default=os.environ.get("FMO_EXPECTED_ROOT_FINGERPRINT"))
    register.set_defaults(function=command_register)

    listing = subparsers.add_parser("list", help="list allocated identities without private material")
    listing.add_argument("--registry")
    listing.set_defaults(function=command_list)
    return parser


def main() -> int:
    try:
        args = build_parser().parse_args()
        return args.function(args)
    except (IssuerError, sqlite3.Error, OSError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
