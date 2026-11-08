#!/usr/bin/env python3
"""Validate the metadata and layout of the unsigned GymForTeenage IPA."""

from __future__ import annotations

import json
import unicodedata
import plistlib
import sys
import zlib
import zipfile
from pathlib import Path


EXPECTED = {
    "CFBundleIdentifier": "com.gymforteenage.app",
    "CFBundleVersion": "1",
    "CFBundleShortVersionString": "1.0",
    "CFBundleDisplayName": "Gym For Teenage",
}
APP_RELATIVE = "Payload/GymForTeenage.app/"


def check(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")
    print(f"PASS: {message}")


def zip_name(info: zipfile.ZipInfo) -> str:
    """Read Info-ZIP Unicode Path extra fields ignored by Python's zipfile."""
    if info.flag_bits & 0x800:
        return info.filename
    original = info.filename.encode("cp437")
    offset = 0
    while offset + 4 <= len(info.extra):
        field_id = int.from_bytes(info.extra[offset:offset + 2], "little")
        field_size = int.from_bytes(info.extra[offset + 2:offset + 4], "little")
        field = info.extra[offset + 4:offset + 4 + field_size]
        if field_id == 0x7075 and len(field) >= 5 and field[0] == 1:
            expected_crc = int.from_bytes(field[1:5], "little")
            if zlib.crc32(original) == expected_crc:
                return field[5:].decode("utf-8")
        offset += 4 + field_size
    return info.filename


def validate_app(app_path: Path) -> dict:
    plist_path = app_path / "Info.plist"
    check(plist_path.is_file(), "app contains Info.plist")
    with plist_path.open("rb") as file:
        info = plistlib.load(file)

    for key, expected in EXPECTED.items():
        actual = info.get(key)
        check(actual == expected, f"{key}={actual!r}")

    icons = info.get("CFBundleIcons", {})
    primary = icons.get("CFBundlePrimaryIcon", {}) if isinstance(icons, dict) else {}
    check(primary.get("CFBundleIconName") == "AppIcon", "Info.plist selects the AppIcon asset")
    check((app_path / "Assets.car").is_file(), "compiled asset catalog Assets.car is present")
    check(not (app_path / "embedded.mobileprovision").exists(), "no embedded provisioning profile (unsigned IPA)")
    check(not (app_path / "_CodeSignature").exists(), "no embedded code signature (unsigned IPA)")
    return info


def validate_catalog(repo: Path) -> None:
    catalog_path = repo / "Assets.xcassets" / "AppIcon.appiconset" / "Contents.json"
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    icons = catalog.get("images", [])
    check(any(i.get("filename") == "AppIcon.png" and i.get("idiom") == "universal" and i.get("size") == "1024x1024" for i in icons),
          "AppIcon catalog has a universal 1024x1024 source image")
    check((catalog_path.parent / "AppIcon.png").is_file(), "AppIcon source PNG is present")


def validate_ipa(ipa_path: Path, repo: Path) -> None:
    with zipfile.ZipFile(ipa_path) as archive:
        entries = [(zip_name(info), info) for info in archive.infolist()]
        names = [name for name, _ in entries]
        files = [name for name in names if not name.endswith("/")]
        check(any(name == APP_RELATIVE + "Info.plist" for name in files), "IPA contains Payload/GymForTeenage.app/Info.plist")
        app_infos = [name for name in files if name.endswith(".app/Info.plist")]
        check(app_infos == [APP_RELATIVE + "Info.plist"], "IPA contains exactly one app at the expected Payload path")
        check(all(name.startswith(APP_RELATIVE) for name in files), "IPA has no extra top-level or nested Payload directory")
        check(APP_RELATIVE + "Assets.car" in files, "IPA contains the compiled icon and asset catalog")
        check(not any(name.endswith("/embedded.mobileprovision") for name in files), "IPA has no embedded provisioning profile")
        check(not any("/_CodeSignature/" in name for name in files), "IPA has no embedded code signature")

        source_images = {unicodedata.normalize("NFC", path.name) for path in (repo / "Assets" / "упражнения").glob("*.png")}
        packaged_images = {
            unicodedata.normalize("NFC", Path(name).name)
            for name in files
            if name.startswith(APP_RELATIVE) and name.lower().endswith(".png")
        }
        missing_images = sorted(source_images - packaged_images)
        check(not missing_images, f"all {len(source_images)} exercise images are included" if not missing_images else f"missing exercise images: {missing_images}")

        info = plistlib.loads(archive.read(APP_RELATIVE + "Info.plist"))
        for key, expected in EXPECTED.items():
            actual = info.get(key)
            check(actual == expected, f"IPA {key}={actual!r}")
        primary = info.get("CFBundleIcons", {}).get("CFBundlePrimaryIcon", {})
        check(primary.get("CFBundleIconName") == "AppIcon", "IPA Info.plist points to AppIcon")


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: validate_ipa.py APP_BUNDLE IPA_FILE")
    app_path = Path(sys.argv[1])
    ipa_path = Path(sys.argv[2])
    repo = Path.cwd()
    validate_catalog(repo)
    validate_app(app_path)
    validate_ipa(ipa_path, repo)
    print("IPA validation complete: structurally packaged for independent ESign signing.")


if __name__ == "__main__":
    main()
