#!/usr/bin/env python3
"""校验应用的中英文 String Catalog 与双语隐私政策。"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path


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


def restore_tracked_file(path: Path, repository_root: Path = ROOT) -> None:
    """当 CI 工作树漏掉已跟踪输入时，从当前 HEAD 恢复完全相同的内容。"""
    if path.is_file():
        return

    try:
        relative_path = path.relative_to(repository_root).as_posix()
    except ValueError as error:
        raise FileNotFoundError(f"{path} 不在仓库目录内") from error

    result = subprocess.run(
        ["git", "-C", str(repository_root), "show", f"HEAD:{relative_path}"],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", errors="replace").strip()
        raise FileNotFoundError(
            f"{path} 不存在，且无法从当前 HEAD 恢复：{detail or 'Git 对象不存在'}"
        )

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(result.stdout)
    print(f"Restored tracked localization input from HEAD: {relative_path}")


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
