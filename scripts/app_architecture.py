"""Thin embedded code and verify single-architecture macOS 14 app bundles."""
import plistlib
import re
import subprocess
import sys
from pathlib import Path


def macho_binaries(root):
    magic = {bytes.fromhex(value) for value in (
        "feedface", "cefaedfe", "feedfacf", "cffaedfe",
        "cafebabe", "bebafeca", "cafebabf", "bfbafeca",
    )}
    binaries = set()
    for path in Path(root).rglob("*"):
        if path.is_file() and not path.is_symlink():
            with path.open("rb") as source:
                if source.read(4) in magic:
                    binaries.add(path.resolve())
    return binaries


def architectures(binary):
    return subprocess.check_output(["xcrun", "lipo", "-archs", str(binary)], text=True).split()


def thin(root, architecture):
    for binary in sorted(macho_binaries(root)):
        slices = architectures(binary)
        if architecture not in slices:
            raise ValueError(f"Missing {architecture} slice: {binary}")
        if slices != [architecture]:
            subprocess.run(
                ["xcrun", "lipo", str(binary), "-thin", architecture, "-output", str(binary)],
                check=True,
            )


def verify(app, architecture):
    app = Path(app).resolve()
    with (app / "Contents/Info.plist").open("rb") as source:
        info = plistlib.load(source)
    if info["LSMinimumSystemVersion"] != "14.0":
        raise ValueError("The application must declare macOS 14.0 as its minimum")
    if not info.get("SUFeedURL", "").endswith(f"/appcast-{architecture}.xml"):
        raise ValueError("The update feed must match the application architecture")
    executable = app / "Contents/MacOS/JoyHarness"
    sparkle = app / "Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle"
    binaries = macho_binaries(app)
    if not {executable, sparkle} <= binaries:
        raise ValueError("Missing application or Sparkle executable")

    for binary in sorted(binaries):
        if architectures(binary) != [architecture]:
            raise ValueError(f"Only {architecture} is allowed: {binary}")
        build = subprocess.check_output(
            ["xcrun", "vtool", "-arch", architecture, "-show-build", str(binary)],
            text=True,
        )
        versions = re.findall(r"^\s*minos\s+(\d+(?:\.\d+)*)\s*$", build, re.MULTILINE)
        if len(versions) != 1:
            raise ValueError(f"Missing minimum system version: {binary} ({architecture})")
        minimum = tuple(int(part) for part in versions[0].split("."))
        minimum = (minimum + (0, 0))[:3]
        if minimum > (14, 0, 0) or (binary == executable and minimum != (14, 0, 0)):
            raise ValueError(f"Unexpected minimum macOS {versions[0]}: {binary} ({architecture})")
    print(f"Verified {len(binaries)} {architecture} executables compatible with macOS 14")


if __name__ == "__main__":
    if len(sys.argv) != 4 or sys.argv[1] not in {"thin", "verify"} or sys.argv[3] not in {"arm64", "x86_64"}:
        sys.exit("usage: app_architecture.py <thin|verify> <bundle> <arm64|x86_64>")
    {"thin": thin, "verify": verify}[sys.argv[1]](sys.argv[2], sys.argv[3])
