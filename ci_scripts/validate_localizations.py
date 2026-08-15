#!/usr/bin/env python3
"""校验应用的中英文 String Catalog 与双语隐私政策。"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Callable, Optional


ROOT = Path(__file__).resolve().parent.parent
CATALOGS = (
    ROOT / "FMOc/Resources/Localizable.xcstrings",
    ROOT / "FMOc/InfoPlist.xcstrings",
    ROOT / "FMOcLiveActivity/Localizable.xcstrings",
    ROOT / "FMOcLiveActivity/InfoPlist.xcstrings",
)
PLACEHOLDER = re.compile(
    r"%(?:\d+\$)?(?:[-+#0 ']*\d*(?:\.\d+)?)?(?:hh|h|ll|l|q|L|z|t|j)?[@a-zA-Z]"
)
POSITION = re.compile(r"^%(?:\d+\$)?")
HAN = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff]", re.UNICODE)
COMMIT_SHA = re.compile(r"^[0-9a-fA-F]{40}$")
GITHUB_RAW_BASE = "https://raw.githubusercontent.com/Johnson-LYS/FMO-Companion"
MAX_RESTORE_BYTES = 5 * 1024 * 1024
ALLOWED_RESTORE_PATHS = frozenset(
    (
        "FMOc/Resources/Localizable.xcstrings",
        "FMOc/InfoPlist.xcstrings",
        "FMOcLiveActivity/Localizable.xcstrings",
        "FMOcLiveActivity/InfoPlist.xcstrings",
        "privacy/index.html",
    )
)

RemoteFetcher = Callable[[str, str], bytes]


def fetch_github_file(commit_sha: str, relative_path: str) -> bytes:
    """从固定公开仓库的精确提交读取白名单文件。"""
    encoded_path = urllib.parse.quote(relative_path, safe="/")
    url = f"{GITHUB_RAW_BASE}/{commit_sha}/{encoded_path}"
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "FMO-Companion-Xcode-Cloud"},
    )

    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            content_length = response.headers.get("Content-Length")
            if content_length and int(content_length) > MAX_RESTORE_BYTES:
                raise FileNotFoundError(f"远程文件超过 {MAX_RESTORE_BYTES} 字节限制")
            payload = response.read(MAX_RESTORE_BYTES + 1)
    except (urllib.error.URLError, TimeoutError, ValueError) as error:
        raise FileNotFoundError(f"无法读取精确提交中的 {relative_path}：{error}") from error

    if len(payload) > MAX_RESTORE_BYTES:
        raise FileNotFoundError(f"远程文件超过 {MAX_RESTORE_BYTES} 字节限制")
    return payload


def xcode_cloud_commit() -> Optional[str]:
    if os.environ.get("CI_XCODE_CLOUD", "").upper() != "TRUE":
        return None
    return os.environ.get("CI_COMMIT")


def restore_tracked_file(
    path: Path,
    repository_root: Path = ROOT,
    commit_sha: Optional[str] = None,
    remote_fetcher: RemoteFetcher = fetch_github_file,
) -> None:
    """恢复源码导出遗漏的固定输入，同时保持内容绑定到精确提交。"""
    if path.is_file():
        return

    try:
        relative_path = path.relative_to(repository_root).as_posix()
    except ValueError as error:
        raise FileNotFoundError(f"{path} 不在仓库目录内") from error

    if relative_path not in ALLOWED_RESTORE_PATHS:
        raise FileNotFoundError(f"{path} 不在允许恢复的输入白名单中")

    git_detail = "工作目录不包含 Git 元数据"
    if (repository_root / ".git").exists():
        result = subprocess.run(
            ["git", "-C", str(repository_root), "show", f"HEAD:{relative_path}"],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        if result.returncode == 0:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(result.stdout)
            print(f"Restored tracked localization input from HEAD: {relative_path}")
            return
        git_detail = result.stderr.decode("utf-8", errors="replace").strip()

    exact_commit = commit_sha if commit_sha is not None else xcode_cloud_commit()
    if not exact_commit:
        raise FileNotFoundError(
            f"{path} 不存在，且无法恢复：{git_detail or 'Git 对象不存在'}"
        )
    if not COMMIT_SHA.fullmatch(exact_commit):
        raise FileNotFoundError("CI_COMMIT 不是有效的 40 位 Git 提交哈希，拒绝远程恢复")

    payload = remote_fetcher(exact_commit.lower(), relative_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(payload)
    print(f"Restored localization input from exact CI commit: {relative_path}")


def placeholder_signature(value: str) -> list[str]:
    return sorted(POSITION.sub("%", token) for token in PLACEHOLDER.findall(value))


def validate_catalog(path: Path) -> list[str]:
    errors: list[str] = []
    restore_tracked_file(path)
    with path.open(encoding="utf-8") as stream:
        catalog = json.load(stream)

    if catalog.get("sourceLanguage") != "en":
        errors.append(f"{path}: sourceLanguage 必须为 en")

    for key, entry in catalog.get("strings", {}).items():
        if not key:
            continue
        localizations = entry.get("localizations", {})
        for language in ("en", "zh-Hans"):
            unit = localizations.get(language, {}).get("stringUnit", {})
            value = unit.get("value", "")
            if not value.strip():
                errors.append(f"{path}: {key!r} 缺少 {language} 文案")
                continue
            if unit.get("state") != "translated":
                errors.append(f"{path}: {key!r} 的 {language} 状态不是 translated")
            if placeholder_signature(key) != placeholder_signature(value):
                errors.append(
                    f"{path}: {key!r} 的 {language} 占位符不一致：{value!r}"
                )
        english = localizations.get("en", {}).get("stringUnit", {}).get("value", "")
        if HAN.search(english):
            errors.append(f"{path}: {key!r} 的英文仍包含中文：{english!r}")
    return errors


def validate_privacy_policy(path: Path) -> list[str]:
    restore_tracked_file(path)
    source = path.read_text(encoding="utf-8")
    errors: list[str] = []
    for language in ("zh-Hans", "en"):
        if f'data-language="{language}"' not in source:
            errors.append(f"{path}: 缺少 {language} 隐私政策正文")
    if "<script" in source.lower():
        errors.append(f"{path}: 隐私政策不得依赖 JavaScript")
    return errors


def main() -> int:
    errors: list[str] = []
    for catalog in CATALOGS:
        errors.extend(validate_catalog(catalog))
    errors.extend(validate_privacy_policy(ROOT / "privacy/index.html"))

    if errors:
        print("Localization validation failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    print("Localization validation passed for en and zh-Hans.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
