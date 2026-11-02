import plistlib
from pathlib import Path
import re
import subprocess
import sys

app = Path(sys.argv[1])
with (app / "Contents/Info.plist").open("rb") as source:
    minimum = plistlib.load(source)["LSMinimumSystemVersion"]


def version(value):
    return tuple((list(map(int, value.split("."))) + [0, 0])[:3])


failures = []
files = [app / "Contents/MacOS/ChiakiNG", *sorted((app / "Contents/Frameworks").glob("*.dylib"))]
for binary in files:
    architectures = subprocess.check_output(["lipo", "-archs", str(binary)], text=True).split()
    if "arm64" not in architectures:
        failures.append(f"{binary.name}: missing arm64")
        continue
    commands = subprocess.check_output(["otool", "-arch", "arm64", "-l", str(binary)], text=True)
    versions = re.findall(r"\bminos\s+([\d.]+)", commands)
    versions += re.findall(r"LC_VERSION_MIN_MACOSX\s+cmdsize\s+\d+\s+version\s+([\d.]+)", commands)
    if not versions:
        failures.append(f"{binary.name}: missing macOS deployment metadata")
    for required in versions:
        if version(required) > version(minimum):
            failures.append(f"{binary.name}: requires macOS {required}, app promises {minimum}")
if failures:
    raise SystemExit("\n".join(failures))
print(f"PASS: {len(files)} bundled binaries support arm64 macOS {minimum}")
