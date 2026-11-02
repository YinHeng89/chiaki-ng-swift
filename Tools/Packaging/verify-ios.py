from pathlib import Path
import re
import subprocess
import sys

PLATFORMS = {"ios": "2", "ios-simulator": "7"}
MINIMUM = (26, 0, 0)
SYSTEM_ROOTS = ("@rpath/", "@executable_path/", "@loader_path/", "/usr/lib/", "/System/Library/")


def version(value):
    return tuple((list(map(int, value.split("."))) + [0, 0])[:3])


ALLOWED = tuple(argument.removeprefix("--allow=").rstrip("/") + "/" for argument in sys.argv[2:]
                if argument.startswith("--allow="))
binaries = [Path(argument) for argument in sys.argv[2:] if not argument.startswith("--allow=")]
if len(sys.argv) < 3 or sys.argv[1] not in PLATFORMS or not binaries:
    raise SystemExit("usage: verify-ios.py ios|ios-simulator [--allow=prefix] binary...")
expected = PLATFORMS[sys.argv[1]]
failures = []
for binary in binaries:
    architectures = subprocess.check_output(["lipo", "-archs", str(binary)], text=True).split()
    if architectures != ["arm64"]:
        failures.append(f"{binary.name}: built for {' '.join(architectures)}, not arm64")
        continue
    commands = subprocess.check_output(["otool", "-l", str(binary)], text=True)
    builds = re.findall(r"LC_BUILD_VERSION\s+cmdsize\s+\d+\s+platform\s+(\d+)\s+minos\s+([\d.]+)", commands)
    if not builds:
        failures.append(f"{binary.name}: missing deployment metadata")
    for platform, required in builds:
        if platform != expected:
            failures.append(f"{binary.name}: built for platform {platform}, not {sys.argv[1]}")
        if version(required) > MINIMUM:
            failures.append(f"{binary.name}: requires iOS {required}, app promises 26.0")
    linked = subprocess.check_output(["otool", "-L", str(binary)], text=True).splitlines()[1:]
    for line in linked:
        name = line.split(" (")[0].strip()
        if not name.startswith(SYSTEM_ROOTS + ALLOWED):
            failures.append(f"{binary.name}: links {name}, which an iOS app cannot load")
if failures:
    raise SystemExit("\n".join(failures))
print(f"PASS: {len(binaries)} binaries support arm64 {sys.argv[1]} 26.0")
