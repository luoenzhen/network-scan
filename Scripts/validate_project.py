"""Portable checks for project resources and Swift vendor dictionary traps."""

import plistlib
import re
from collections import Counter
from pathlib import Path


def validate(root):
    errors = []
    database = (root / "NetScan/Models/OUIVendorDatabase.swift").read_text(encoding="utf-8")
    prefixes = re.findall(r'^\s*"([0-9A-F]{6})":', database, re.MULTILINE)
    for prefix, count in Counter(prefixes).items():
        if count > 1:
            errors.append(f"Duplicate vendor prefix {prefix}: Swift dictionary initialization will crash")

    with (root / "NetScan/Resources/Info.plist").open("rb") as source:
        info = plistlib.load(source)
    bonjour = (root / "NetScan/Services/BonjourDiscoveryService.swift").read_text(encoding="utf-8")
    for service in re.findall(r'"(_[^\"]+\._tcp)"', bonjour):
        if service not in info.get("NSBonjourServices", []):
            errors.append(f"Bonjour service missing from Info.plist: {service}")

    project = (root / "NetScan/NetScan.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
    for source in (root / "NetScan").rglob("*.swift"):
        if f"{source.name} in Sources" not in project:
            errors.append(f"Swift source missing from Xcode build: {source.name}")
    return errors


if __name__ == "__main__":
    problems = validate(Path(__file__).resolve().parent.parent)
    for problem in problems:
        print(problem)
    if problems:
        raise SystemExit(1)
    print("Project resource and vendor dictionary checks passed.")
