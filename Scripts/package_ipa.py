#!/usr/bin/env python3
"""Package an Xcode-built iPhoneOS .app for sideloading (does not compile Swift)."""

import argparse
import os
import plistlib
import struct
import tempfile
import zipfile
from pathlib import Path


def package_app(app_path, output_path):
    app_path = Path(app_path).resolve()
    output_path = Path(output_path).resolve()
    if not app_path.is_dir() or app_path.suffix != ".app":
        raise ValueError("Provide a compiled iPhoneOS .app directory from Xcode or CI.")
    with (app_path / "Info.plist").open("rb") as source:
        info = plistlib.load(source)
    executable = info.get("CFBundleExecutable", "")
    if not executable or Path(executable).name != executable or "$" in executable:
        raise ValueError("The app's CFBundleExecutable must be resolved by Xcode.")
    if "iPhoneOS" not in info.get("CFBundleSupportedPlatforms", []):
        raise ValueError("An iPhoneOS build is required; simulator/source bundles cannot be sideloaded.")
    binary = app_path / executable
    with binary.open("rb") as source:
        header = source.read(32)
    if len(header) != 32:
        raise ValueError("Missing compiled ARM64 executable.")
    magic, cpu, _, kind, commands, command_bytes, _, _ = struct.unpack("<8I", header)
    if (magic, cpu, kind) != (0xFEEDFACF, 0x0100000C, 2) or commands == 0 or command_bytes == 0:
        raise ValueError("A compiled ARM64 Mach-O executable is required; placeholder binaries are invalid.")
    if binary.stat().st_size <= 32 + command_bytes:
        raise ValueError("The executable is truncated.")
    if output_path == app_path or app_path in output_path.parents:
        raise ValueError("The output IPA must be outside the app bundle.")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    handle, temporary = tempfile.mkstemp(suffix=".ipa", dir=output_path.parent)
    os.close(handle)
    try:
        with zipfile.ZipFile(temporary, "w", zipfile.ZIP_DEFLATED) as archive:
            for source in sorted(app_path.rglob("*")):
                if source.is_file():
                    name = Path("Payload") / app_path.name / source.relative_to(app_path)
                    entry = zipfile.ZipInfo.from_file(source, arcname=name.as_posix())
                    permissions = 0o755 if source == binary or os.access(source, os.X_OK) else 0o644
                    entry.create_system = 3
                    entry.external_attr = (0o100000 | permissions) << 16
                    entry.compress_type = zipfile.ZIP_DEFLATED
                    archive.writestr(entry, source.read_bytes())
        os.replace(temporary, output_path)
    finally:
        Path(temporary).unlink(missing_ok=True)
    return output_path


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path, help="Compiled NetScan.app from an iPhoneOS archive")
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parent.parent / "NetScan.ipa")
    arguments = parser.parse_args()
    try:
        result = package_app(arguments.app, arguments.output)
    except (ValueError, OSError, plistlib.InvalidFileException) as error:
        parser.exit(1, f"Packaging failed: {error}\n")
    print(f"Packaged {result}. AltStore must sign it before installation.")
