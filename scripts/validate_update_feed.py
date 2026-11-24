"""Validate generated metadata against the sealed application in its DMG."""
import base64
import plistlib
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def read_dmg_info(archive):
    attached = subprocess.run(
        ["hdiutil", "attach", "-plist", "-nobrowse", "-readonly", str(archive)],
        check=True,
        capture_output=True,
    )
    mount_point = None
    device = None
    try:
        details = plistlib.loads(attached.stdout)
        for entity in details.get("system-entities", []):
            mount_point = entity.get("mount-point")
            if mount_point:
                device = entity.get("dev-entry")
                break
        if not mount_point:
            raise ValueError("DMG did not contain a mounted volume")
        info_path = Path(mount_point) / "JoyHarness.app/Contents/Info.plist"
        if not info_path.is_file():
            raise ValueError("DMG does not contain JoyHarness.app")
        return plistlib.loads(info_path.read_bytes())
    finally:
        target = device or mount_point
        if target:
            subprocess.run(["hdiutil", "detach", target, "-quiet"], check=True)


def validate(feed, archive, tag, repository, architecture):
    if architecture not in {"arm64", "x86_64"}:
        raise ValueError("Unsupported target architecture")
    if Path(archive).name != f"JoyHarness-{tag}-macos-{architecture}.dmg":
        raise ValueError("Archive name must match the target architecture")
    if Path(feed).name != f"appcast-{architecture}.xml":
        raise ValueError("Feed name must match the target architecture")
    ns = {"s": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
    info = read_dmg_info(archive)
    expected_feed = f"https://github.com/{repository}/releases/latest/download/appcast-{architecture}.xml"
    if info.get("SUFeedURL") != expected_feed:
        raise ValueError("Application update feed does not match the target architecture or repository")
    items = ET.parse(feed).findall("./channel/item")
    if len(items) != 1:
        raise ValueError("The release feed must contain exactly one update")
    item = items[0]
    enclosure = item.find("enclosure")
    if enclosure is None:
        raise ValueError("Missing update enclosure")
    signature = enclosure.get("{" + ns["s"] + "}edSignature", "")
    if len(base64.b64decode(signature, validate=True)) != 64:
        raise ValueError("Missing or invalid EdDSA signature")
    expected = {
        "s:version": info["CFBundleVersion"],
        "s:shortVersionString": tag.removeprefix("v"),
        "s:minimumSystemVersion": info["LSMinimumSystemVersion"],
    }
    for key, value in expected.items():
        if item.findtext(key, namespaces=ns) != value:
            raise ValueError(f"Appcast {key} differs from the shipped application")
    if info["CFBundleShortVersionString"] != tag.removeprefix("v"):
        raise ValueError("App version differs from release tag")
    if enclosure.get("length") != str(Path(archive).stat().st_size):
        raise ValueError("Update archive size mismatch")
    url = f"https://github.com/{repository}/releases/download/{tag}/{Path(archive).name}"
    if enclosure.get("url") != url:
        raise ValueError("Unexpected download URL")


if __name__ == "__main__":
    validate(*sys.argv[1:])
