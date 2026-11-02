import fnmatch
import hashlib
import json
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tarfile

from sources import CACHE, MIRROR_REPOSITORY, SOURCES, digest_of, fetch

RELEASE_PREFIX = "darwin-deps-"
RELEASES = f"https://api.github.com/repos/{MIRROR_REPOSITORY}/releases?per_page=100"
DOWNLOADS = f"https://github.com/{MIRROR_REPOSITORY}/releases/download"
ARCHIVE = "build.tar.gz"
PACKAGED = {"openssl": "openssl", "nghttp2": "nghttp2", "curl": "curl", "ffmpeg": "ffmpeg", "opus": "opus",
            "miniupnpc": "miniupnpc"}
NOTICES = ("COPYING*", "LICENSE*", "COPYRIGHT*")
MACH_O = (b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe")
BUILDER = Path(__file__).with_name("build.py")
LABELS = {"macos": "macOS", "ios": "iOS", "ios-simulator": "the iOS simulator"}


class Unavailable(Exception):
    pass


def download(url, target):
    partial = target.with_suffix(target.suffix + ".partial")
    partial.unlink(missing_ok=True)
    result = subprocess.run(["/usr/bin/curl", "--fail", "--silent", "--show-error", "--location",
                             "--retry", "3", "--output", str(partial), url])
    if result.returncode:
        partial.unlink(missing_ok=True)
        raise SystemExit(f"Download failed: {url}")
    partial.replace(target)


def latest_tag():
    listed = subprocess.run(["/usr/bin/curl", "--fail", "--silent", "--show-error", "--location",
                             "--retry", "3", RELEASES], capture_output=True, text=True)
    if listed.returncode:
        raise SystemExit(f"Could not list releases of {MIRROR_REPOSITORY}: {listed.stderr.strip()}")
    releases = [release for release in json.loads(listed.stdout)
                if release["tag_name"].startswith(RELEASE_PREFIX) and not release["draft"]]
    if not releases:
        raise SystemExit(f"{MIRROR_REPOSITORY} has no {RELEASE_PREFIX}* release")
    return max(releases, key=lambda release: release["published_at"])["tag_name"]


def fetched(tag):
    folder = CACHE / tag
    folder.mkdir(parents=True, exist_ok=True)
    for name in ("build.json", ARCHIVE + ".sha256"):
        download(f"{DOWNLOADS}/{tag}/{name}", folder / name)
    described = json.loads((folder / "build.json").read_text())
    expected = (folder / (ARCHIVE + ".sha256")).read_text().split()[0]
    listed = {entry["file"]: entry["sha256"] for entry in described["files"]}
    if listed.get(ARCHIVE) != expected:
        raise SystemExit(f"{tag}: build.json and {ARCHIVE}.sha256 disagree")
    archive = folder / ARCHIVE
    if not archive.exists() or digest_of(archive) != expected:
        download(f"{DOWNLOADS}/{tag}/{ARCHIVE}", archive)
    if digest_of(archive) != expected:
        archive.unlink()
        raise SystemExit(f"SHA-256 mismatch: {tag}/{ARCHIVE}")
    return archive, described, expected


def local(folder):
    archive = folder / ARCHIVE
    described = sorted(folder.glob("build*.json"))
    if not archive.is_file() or not described:
        raise SystemExit(f"{folder} has no {ARCHIVE} with its build json; run make package in native-deps")
    return archive, json.loads(described[0].read_text()), digest_of(archive)


def require_pins(tag, described, target):
    listed = described["deps"] if target == "macos" else described.get("targets", {}).get(target)
    if listed is None:
        raise Unavailable(f"{tag} has no build for it")
    built = {entry["name"]: entry for entry in listed}
    for name, packaged in PACKAGED.items():
        version, _, digest = SOURCES[name]
        entry = built.get(packaged)
        if entry is None:
            raise SystemExit(f"{tag} has no {packaged} for {LABELS[target]}; build from source instead")
        if (entry["version"], entry["sha256"]) != (version, digest):
            raise SystemExit(f"{tag} built {packaged} {entry['version']}, but this checkout pins "
                             f"{version}; build from source instead")
        if (entry["arch"], entry.get("target", "macos"), entry["deployment_target"]) != ("arm64", target, "26.0"):
            raise SystemExit(f"{tag} built {packaged} for {entry['arch']} {entry.get('target', 'macos')} "
                             f"{entry['deployment_target']}, not arm64 {LABELS[target]} 26.0")


def unpacked(archive, staging):
    shutil.rmtree(staging, ignore_errors=True)
    staging.mkdir(parents=True)
    with tarfile.open(archive) as bundle:
        bundle.extractall(staging, filter="data")
    for line in (staging / "SHA256SUMS").read_text().splitlines():
        digest, relative = line.split(maxsplit=1)
        member = staging / relative
        if not member.is_file() or digest_of(member) != digest:
            raise SystemExit(f"SHA-256 mismatch inside {archive.name}: {relative}")
    return staging


def built_locations(staging):
    for packaged in PACKAGED.values():
        for described in sorted((staging / packaged).glob("lib/pkgconfig/*.pc")):
            for line in described.read_text().splitlines():
                if line.startswith("prefix="):
                    pool = Path(line.removeprefix("prefix=")).parent
                    return sorted((f"{pool}/{folder.name}" for folder in staging.iterdir()
                                   if folder.is_dir()), key=len, reverse=True)
    raise SystemExit("The prebuilt archive does not say where it was built")


def is_mach_o(path):
    with path.open("rb") as binary:
        return binary.read(4) in MACH_O


def relocate_text(path, locations, prefix):
    try:
        text = path.read_text()
    except UnicodeDecodeError:
        return
    moved = text
    for location in locations:
        moved = moved.replace(location, str(prefix))
    if moved != text:
        path.write_text(moved)


def relocate_binary(path, locations):
    linked = subprocess.check_output(["otool", "-L", str(path)], text=True).splitlines()[1:]
    identity = subprocess.check_output(["otool", "-D", str(path)], text=True).splitlines()[1:]
    changes = []
    borrows = False
    for line in linked:
        name = line.split(" (")[0].strip()
        if any(name.startswith(location + "/") for location in locations):
            target = f"@rpath/{Path(name).name}"
            if name in identity:
                changes += ["-id", target]
            else:
                changes += ["-change", name, target]
                borrows = True
    if borrows:
        changes += ["-add_rpath", "@loader_path" if path.suffix == ".dylib" else "@executable_path/../lib"]
    if changes:
        subprocess.run(["install_name_tool", *changes, str(path)], check=True, capture_output=True)
        subprocess.run(["codesign", "--force", "--sign", "-", str(path)], check=True, capture_output=True)


def write_notices(prefix):
    for name in PACKAGED:
        version, upstream, digest = SOURCES[name]
        notices = prefix / "share/licenses" / name
        notices.mkdir(parents=True, exist_ok=True)
        with tarfile.open(fetch(name)) as source:
            for member in source:
                parts = Path(member.name).parts
                if member.isfile() and len(parts) == 2 and any(
                        fnmatch.fnmatch(parts[1], pattern) for pattern in NOTICES):
                    (notices / parts[1]).write_bytes(source.extractfile(member).read())
        (notices / "SOURCE.txt").write_text(f"{upstream}\nSHA-256: {digest}\n")


def install(tag, target, folder=None):
    located = subprocess.run([sys.executable, str(BUILDER), f"--platform={target}", "--prefix"],
                             capture_output=True, text=True)
    if located.returncode:
        raise Unavailable("its SDK is not installed")
    prefix = Path(located.stdout.strip())
    root = prefix.parent
    stamps = [root / f"{name}.complete" for name in PACKAGED]
    if all(stamp.exists() for stamp in stamps):
        print(f"Pinned dependencies are already installed in {prefix}")
        return
    if prefix.exists() or any(stamp.exists() for stamp in stamps):
        raise SystemExit(f"{root} holds a partial dependency build; run make clean first")
    archive, described, digest = local(folder) if folder else fetched(tag)
    require_pins(tag, described, target)
    staging = unpacked(archive, root / "prebuilt")
    built = staging if target == "macos" else staging / target
    locations = built_locations(built)
    assembled = root / "prefix.partial"
    shutil.rmtree(assembled, ignore_errors=True)
    for packaged in PACKAGED.values():
        shutil.copytree(built / packaged, assembled, dirs_exist_ok=True,
                        ignore=shutil.ignore_patterns("BUILD-INFO"))
    for path in sorted(assembled.rglob("*")):
        if not path.is_file() or path.is_symlink():
            continue
        if path.parent.name == "bin":
            path.chmod(0o755)
        if is_mach_o(path):
            relocate_binary(path, locations)
        else:
            relocate_text(path, locations, prefix)
    write_notices(assembled)
    (assembled / "share/licenses/prebuilt.json").write_text(json.dumps(
        {"release": tag, "archive_sha256": digest, "revision": described["revision"]}, indent=2) + "\n")
    assembled.replace(prefix)
    shutil.rmtree(staging)
    binaries = {binary.name: digest_of(binary)
                for binary in sorted([*(prefix / "lib").glob("*.dylib"), *(prefix / "lib").glob("*.a")])
                if not binary.is_symlink()}
    for stamp in stamps:
        stamp.write_text(json.dumps(binaries, sort_keys=True, indent=2) + "\n")
    print(f"Installed {tag} into {prefix}")


if __name__ == "__main__":
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        raise SystemExit("Pinned dependencies require an Apple silicon Mac running natively")
    chosen = [argument.removeprefix("--platform=") for argument in sys.argv[1:]
              if argument.startswith("--platform=")]
    folders = [Path(argument.removeprefix("--from=")).resolve() for argument in sys.argv[1:]
               if argument.startswith("--from=")]
    dates = [argument for argument in sys.argv[1:] if not argument.startswith("--")]
    if (len(dates) > 1 or len(chosen) > 1 or len(folders) > 1 or (dates and folders)
            or any(target not in LABELS for target in chosen)):
        raise SystemExit("usage: prebuilt.py [--platform=macos|ios|ios-simulator] [--from=folder | date]")
    folder = folders[0] if folders else None
    tag = str(folder) if folder else RELEASE_PREFIX + dates[0] if dates else latest_tag()
    for target in chosen or LABELS:
        try:
            install(tag, target, folder)
        except Unavailable as reason:
            if chosen or target == "macos":
                raise SystemExit(f"No prebuilt dependencies for {LABELS[target]}: {reason}; "
                                 "build from source instead")
            print(f"Skipped {LABELS[target]}: {reason}")
