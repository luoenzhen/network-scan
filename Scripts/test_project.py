import plistlib
import struct
import tempfile
import unittest
import zipfile
from pathlib import Path

from package_ipa import package_app
from validate_project import validate


class ProjectTests(unittest.TestCase):
    def test_project_resources_and_vendor_prefixes(self):
        self.assertEqual(validate(Path(__file__).resolve().parent.parent), [])

    def test_duplicate_vendor_regression_is_detected(self):
        root = Path(__file__).resolve().parent.parent
        with tempfile.TemporaryDirectory() as directory:
            fixture = Path(directory)
            import shutil
            shutil.copytree(root / "NetScan", fixture / "NetScan")
            source = fixture / "NetScan/Models/OUIVendorDatabase.swift"
            source.write_text(source.read_text(encoding="utf-8") + '\n    "001E67": ("duplicate", .computer),\n', encoding="utf-8")
            self.assertTrue(any("Duplicate vendor prefix 001E67" in error for error in validate(fixture)))

    def make_app(self, root):
        app = root / "NetScan.app"
        app.mkdir()
        self.write_info(app, {"CFBundleExecutable": "NetScan", "CFBundleSupportedPlatforms": ["iPhoneOS"]})
        # Structural fixture only, not a runnable Apple executable.
        (app / "NetScan").write_bytes(struct.pack("<8I", 0xFEEDFACF, 0x0100000C, 0, 2, 1, 8, 0, 0) + b"\0" * 32)
        return app

    def write_info(self, app, info):
        with (app / "Info.plist").open("wb") as output:
            plistlib.dump(info, output)

    def test_package_structure_permissions_and_stale_entries(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = self.make_app(root)
            extra = app / "old-resource.txt"
            extra.write_text("old")
            output = root / "NetScan.ipa"
            package_app(app, output)
            extra.unlink()
            package_app(app, output)
            with zipfile.ZipFile(output) as archive:
                self.assertEqual(sorted(archive.namelist()), ["Payload/NetScan.app/Info.plist", "Payload/NetScan.app/NetScan"])
                self.assertEqual((archive.getinfo("Payload/NetScan.app/NetScan").external_attr >> 16) & 0o777, 0o755)

    def test_rejects_placeholder_and_preserves_existing_ipa(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = self.make_app(root)
            (app / "NetScan").write_bytes(struct.pack("<8I", 0xFEEDFACF, 0x0100000C, 0, 2, 0, 0, 0, 0) + b"\0" * 4064)
            output = root / "NetScan.ipa"
            output.write_bytes(b"previous build")
            with self.assertRaisesRegex(ValueError, "placeholder"):
                package_app(app, output)
            self.assertEqual(output.read_bytes(), b"previous build")

    def test_rejects_simulator_unresolved_plist_and_output_inside_app(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = self.make_app(root)
            self.write_info(app, {"CFBundleExecutable": "$(EXECUTABLE_NAME)"})
            with self.assertRaisesRegex(ValueError, "resolved"):
                package_app(app, root / "output.ipa")
            self.write_info(app, {"CFBundleExecutable": "NetScan", "CFBundleSupportedPlatforms": ["iPhoneSimulator"]})
            with self.assertRaisesRegex(ValueError, "iPhoneOS"):
                package_app(app, root / "output.ipa")
            self.write_info(app, {"CFBundleExecutable": "NetScan", "CFBundleSupportedPlatforms": ["iPhoneOS"]})
            with self.assertRaisesRegex(ValueError, "outside"):
                package_app(app, app / "output.ipa")


if __name__ == "__main__":
    unittest.main()
