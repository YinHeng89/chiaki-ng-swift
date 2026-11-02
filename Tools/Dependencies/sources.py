import hashlib
from pathlib import Path
import subprocess
import sys

PROJECT = Path(__file__).resolve().parents[2]
CACHE = PROJECT / ".build/downloads"
MIRROR_REPOSITORY = "chiaki-ng/native-deps"
MIRROR_RELEASE = "sources"
MIRROR = f"https://github.com/{MIRROR_REPOSITORY}/releases/download/{MIRROR_RELEASE}"
SOURCES = {
    "ffmpeg": ("9.0.2", "https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz",
               "8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e"),
    "openssl": ("3.6.4", "https://github.com/openssl/openssl/releases/download/openssl-3.6.4/openssl-3.6.4.tar.gz",
                "9bffaa1ad1e07b354c21bd3324ec02fa15579f45a7d0494b3e74bc449b7333ef"),
    "nghttp2": ("1.70.0", "https://github.com/nghttp2/nghttp2/releases/download/v1.70.0/nghttp2-1.70.0.tar.xz",
                "e05cb1388eaca3830aded4ccf20044b6e1ac1a61411dcca11b0437c4285c8bc2"),
    "curl": ("8.22.0", "https://curl.se/download/curl-8.22.0.tar.bz2",
             "5d956a6a22b3c279f50c421ee5d3c9e9d660cb6f115dcf881b579e952130549c"),
    "opus": ("1.6.1", "https://downloads.xiph.org/releases/opus/opus-1.6.1.tar.gz",
             "6ffcb593207be92584df15b32466ed64bbec99109f007c82205f0194572411a1"),
    "miniupnpc": ("2.3.3", "https://miniupnp.tuxfamily.org/files/miniupnpc-2.3.3.tar.gz",
                  "d52a0afa614ad6c088cc9ddff1ae7d29c8c595ac5fdd321170a05f41e634bd1a"),
    "SDL3": ("3.4.16", "https://github.com/libsdl-org/SDL/releases/download/release-3.4.16/SDL3-3.4.16.tar.gz",
             "7322236cd12090c3eb40b9728be4d49c76f66ad17d04369584d4ecad5cf77c68"),
}


def filename(name):
    return SOURCES[name][1].rsplit("/", 1)[1]


def digest_of(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fetch(name):
    _, upstream, digest = SOURCES[name]
    CACHE.mkdir(parents=True, exist_ok=True)
    archive = CACHE / filename(name)
    if archive.exists():
        if digest_of(archive) != digest:
            raise SystemExit(f"SHA-256 mismatch: {archive}; remove it before retrying")
        return archive
    partial = archive.with_suffix(archive.suffix + ".partial")
    for url in (f"{MIRROR}/{filename(name)}", upstream):
        partial.unlink(missing_ok=True)
        result = subprocess.run(["/usr/bin/curl", "--fail", "--silent", "--show-error", "--location",
                                 "--retry", "3", "--output", str(partial), url])
        if result.returncode == 0 and digest_of(partial) == digest:
            partial.replace(archive)
            return archive
        print(f"Skipping {url}: download failed or SHA-256 did not match", file=sys.stderr)
    partial.unlink(missing_ok=True)
    raise SystemExit(f"No source for {name} matched SHA-256 {digest}")


def mirror():
    listed = subprocess.run(["gh", "release", "view", MIRROR_RELEASE, "--repo", MIRROR_REPOSITORY,
                             "--json", "assets", "--jq", ".assets[].name"], capture_output=True, text=True)
    if listed.returncode:
        subprocess.run(["gh", "release", "create", MIRROR_RELEASE, "--repo", MIRROR_REPOSITORY,
                        "--title", "Pinned dependency sources",
                        "--notes", "Source archives pinned by chiaki-ng for macOS. Builds verify each SHA-256."],
                       check=True)
        present = set()
    else:
        present = set(listed.stdout.split())
    for name in SOURCES:
        archive = fetch(name)
        if archive.name in present:
            print(f"Mirrored: {archive.name}")
            continue
        subprocess.run(["gh", "release", "upload", MIRROR_RELEASE, str(archive), "--repo", MIRROR_REPOSITORY],
                       check=True)
        print(f"Uploaded: {archive.name}")


if __name__ == "__main__":
    if sys.argv[1:] == ["--mirror"]:
        mirror()
    elif sys.argv[1:] == ["--fetch"]:
        for source_name in SOURCES:
            print(fetch(source_name))
    else:
        raise SystemExit("usage: sources.py --mirror | --fetch")
