import fcntl
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import sys

from sources import SOURCES, fetch

PROJECT = Path(__file__).resolve().parents[2]
BUILT = ("openssl", "nghttp2", "curl", "ffmpeg", "opus", "miniupnpc")
STATIC_OPTIONS = {
    "nghttp2": ["-DENABLE_LIB_ONLY=ON", "-DBUILD_STATIC_LIBS=ON", "-DENABLE_DOC=OFF"],
    "opus": ["-DOPUS_BUILD_TESTING=OFF", "-DOPUS_BUILD_PROGRAMS=OFF", "-DOPUS_INSTALL_PKG_CONFIG_MODULE=ON",
             "-DOPUS_INSTALL_CMAKE_CONFIG_MODULE=ON"],
    "miniupnpc": ["-DUPNPC_BUILD_STATIC=ON", "-DUPNPC_BUILD_SHARED=OFF", "-DUPNPC_BUILD_TESTS=OFF",
                  "-DUPNPC_BUILD_SAMPLE=OFF"],
}
EXCLUDED_PREFIXES = "/opt/homebrew;/usr/local;/opt/local"
CROSS_SEARCH = [f"-DCMAKE_FIND_ROOT_PATH_MODE_{kind}=BOTH" for kind in ("PACKAGE", "LIBRARY", "INCLUDE")]
PLATFORMS = {
    "macos": {"sdk": "macosx", "minimum": "-mmacosx-version-min=26.0", "label": "macOS 26", "cmake": [],
              "openssl": [], "ffmpeg": []},
    "ios": {"sdk": "iphoneos", "minimum": "-mios-version-min=26.0", "label": "iOS 26",
            "cmake": ["-DCMAKE_SYSTEM_NAME=iOS", "-DCMAKE_OSX_SYSROOT=iphoneos", *CROSS_SEARCH],
            "openssl": ["no-async", "no-apps"], "ffmpeg": ["--enable-cross-compile"]},
    "ios-simulator": {"sdk": "iphonesimulator", "minimum": "-mios-simulator-version-min=26.0",
                      "label": "the iOS 26 simulator",
                      "cmake": ["-DCMAKE_SYSTEM_NAME=iOS", "-DCMAKE_OSX_SYSROOT=iphonesimulator", *CROSS_SEARCH],
                      "openssl": ["no-async", "no-apps"], "ffmpeg": ["--enable-cross-compile"]},
}
ARGUMENTS = [argument for argument in sys.argv[1:] if not argument.startswith("--platform=")]
PLATFORM_NAME = next((argument.removeprefix("--platform=") for argument in sys.argv[1:]
                      if argument.startswith("--platform=")), os.environ.get("CHIAKI_PLATFORM") or "macos")
if PLATFORM_NAME not in PLATFORMS:
    raise SystemExit(f"Unknown platform {PLATFORM_NAME}; choose one of {', '.join(PLATFORMS)}")
TARGET = PLATFORMS[PLATFORM_NAME]
CROSS = PLATFORM_NAME != "macos"
SDK = subprocess.check_output(["xcrun", "--sdk", TARGET["sdk"], "--show-sdk-path"], text=True).strip()
COMPILER = subprocess.check_output(["xcrun", "clang", "--version"])
TOOLCHAIN = {
    "sdk": subprocess.check_output(["xcrun", "--sdk", TARGET["sdk"], "--show-sdk-version"], text=True).strip(),
    "clang": COMPILER.decode().strip(),
    "cmake": subprocess.check_output(["cmake", "--version"], text=True).splitlines()[0],
    "ninja": subprocess.check_output(["ninja", "--version"], text=True).strip(),
}
KEY = hashlib.sha256(Path(__file__).read_bytes() + json.dumps({name: SOURCES[name] for name in BUILT}, sort_keys=True).encode() + SDK.encode()
                     + json.dumps(TOOLCHAIN, sort_keys=True).encode()).hexdigest()[:16]
ROOT = PROJECT / ".build/dependencies" / KEY
PREFIX = ROOT / "prefix"
ENV = {key: value for key, value in os.environ.items()
       if key in ("PATH", "HOME", "TMPDIR", "DEVELOPER_DIR")}
ENV.update(SDKROOT=SDK, LC_ALL="C", TZ="UTC",
           CC=subprocess.check_output(["xcrun", "--find", "clang"], text=True).strip(),
           CXX=subprocess.check_output(["xcrun", "--find", "clang++"], text=True).strip(),
           CFLAGS=f"-arch arm64 {TARGET['minimum']}",
           LDFLAGS=f"-arch arm64 {TARGET['minimum']}",
           PKG_CONFIG_PATH=str(PREFIX / "lib/pkgconfig"))
ENV["IPHONEOS_DEPLOYMENT_TARGET" if CROSS else "MACOSX_DEPLOYMENT_TARGET"] = "26.0"
OPENSSL_ENV = {key: value for key, value in ENV.items() if key not in ("CFLAGS", "LDFLAGS")}
JOBS = str(os.cpu_count() or 4)


def run(arguments, directory, log, env=ENV):
    with log.open("a") as output:
        output.write("\n" + repr(arguments) + "\n")
        output.flush()
        result = subprocess.run(arguments, cwd=directory, env=env, stdout=output, stderr=subprocess.STDOUT)
    if result.returncode:
        print("\n".join(log.read_text(errors="replace").splitlines()[-60:]), file=sys.stderr)
        raise SystemExit(f"Dependency build failed; see {log}")


def source(name):
    version = SOURCES[name][0]
    archive = fetch(name)
    directory = ROOT / f"{name}-{version}"
    if not directory.exists():
        subprocess.run(["tar", "-xf", str(archive), "-C", str(ROOT)], check=True)
    return directory


def build(name):
    stamp = ROOT / f"{name}.complete"
    if stamp.exists():
        for filename, digest in json.loads(stamp.read_text()).items():
            binary = PREFIX / "lib" / filename
            if not binary.is_file() or hashlib.sha256(binary.read_bytes()).hexdigest() != digest:
                raise SystemExit(f"Dependency cache is incomplete or modified: {binary}; run make clean")
        return
    directory = source(name)
    log = ROOT / f"{name}.log"
    print(f"Building pinned {name} {SOURCES[name][0]} for arm64 {TARGET['label']}; log: {log}", flush=True)
    if name == "openssl":
        run(["./Configure", "darwin64-arm64-cc", "shared", "no-tests", "no-module", "no-legacy",
             TARGET["minimum"], *TARGET["openssl"], f"--prefix={PREFIX}", "--libdir=lib"], directory, log, OPENSSL_ENV)
        run(["make", "-j", JOBS], directory, log, OPENSSL_ENV)
        run(["make", "install_sw"], directory, log, OPENSSL_ENV)
    elif name in STATIC_OPTIONS:
        run(["cmake", "-S", str(directory), "-B", str(directory / "build"), "-G", "Ninja",
             f"-DCMAKE_INSTALL_PREFIX={PREFIX}", "-DCMAKE_INSTALL_LIBDIR=lib",
             f"-DCMAKE_PREFIX_PATH={PREFIX}", f"-DCMAKE_IGNORE_PREFIX_PATH={EXCLUDED_PREFIXES}",
             "-DCMAKE_FIND_USE_PACKAGE_REGISTRY=OFF", "-DCMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY=OFF",
             "-DCMAKE_BUILD_TYPE=Release", "-DCMAKE_OSX_ARCHITECTURES=arm64",
             "-DCMAKE_OSX_DEPLOYMENT_TARGET=26.0", "-DBUILD_SHARED_LIBS=OFF",
             "-DCMAKE_POSITION_INDEPENDENT_CODE=ON", "-DBUILD_TESTING=OFF", *TARGET["cmake"],
             *STATIC_OPTIONS[name]],
            directory, log)
        run(["cmake", "--build", "build", "--parallel", JOBS], directory, log)
        run(["cmake", "--install", "build"], directory, log)
    elif name == "curl":
        run(["cmake", "-S", str(directory), "-B", str(directory / "build"), "-G", "Ninja",
             f"-DCMAKE_INSTALL_PREFIX={PREFIX}", "-DCMAKE_INSTALL_LIBDIR=lib",
             "-DCMAKE_BUILD_TYPE=Release", "-DCMAKE_OSX_ARCHITECTURES=arm64",
             "-DCMAKE_OSX_DEPLOYMENT_TARGET=26.0", "-DBUILD_SHARED_LIBS=ON",
             f"-DCMAKE_IGNORE_PREFIX_PATH={EXCLUDED_PREFIXES}",
             "-DBUILD_STATIC_LIBS=OFF", "-DBUILD_CURL_EXE=OFF", "-DBUILD_TESTING=OFF",
             "-DBUILD_LIBCURL_DOCS=OFF", "-DBUILD_MISC_DOCS=OFF",
             "-DCURL_USE_OPENSSL=ON", f"-DOPENSSL_ROOT_DIR={PREFIX}",
             "-DUSE_APPLE_SECTRUST=ON", "-DCURL_CA_BUNDLE=none", "-DCURL_CA_PATH=none",
             "-DCURL_USE_LIBPSL=OFF", "-DCURL_USE_LIBSSH2=OFF", "-DCURL_USE_LIBSSH=OFF",
             "-DUSE_NGHTTP2=ON", f"-DCMAKE_PREFIX_PATH={PREFIX}", "-DUSE_NGTCP2=OFF", "-DUSE_LIBIDN2=OFF",
             "-DCURL_BROTLI=OFF", "-DCURL_ZSTD=OFF", "-DCURL_ZLIB=OFF",
             "-DCURL_DISABLE_LDAP=ON", "-DCURL_DISABLE_LDAPS=ON", *TARGET["cmake"]], directory, log)
        run(["cmake", "--build", "build", "--parallel", JOBS], directory, log)
        run(["cmake", "--install", "build"], directory, log)
    else:
        run(["./configure", f"--prefix={PREFIX}", "--arch=arm64", "--target-os=darwin",
             f"--cc={ENV['CC']}", f"--sysroot={SDK}", f"--extra-cflags={TARGET['minimum']}",
             f"--extra-ldflags={TARGET['minimum']}", *TARGET["ffmpeg"], "--enable-shared", "--disable-static",
             "--disable-autodetect", "--disable-everything", "--disable-programs", "--disable-doc",
             "--disable-avdevice", "--disable-avfilter", "--disable-swresample", "--disable-swscale",
             "--enable-avcodec", "--enable-avutil", "--enable-avformat", "--enable-videotoolbox",
             "--enable-decoder=h264,hevc", "--enable-parser=h264,hevc",
             "--enable-hwaccel=h264_videotoolbox,hevc_videotoolbox",
             "--enable-demuxer=mov,h264,hevc", "--enable-protocol=file"], directory, log)
        run(["make", "-j", JOBS], directory, log)
        run(["make", "install"], directory, log)
    notices = PREFIX / "share/licenses" / name
    notices.mkdir(parents=True, exist_ok=True)
    for pattern in ("COPYING*", "LICENSE*", "COPYRIGHT*"):
        for license_file in directory.glob(pattern):
            if license_file.is_file():
                (notices / license_file.name).write_bytes(license_file.read_bytes())
    (notices / "SOURCE.txt").write_text(f"{SOURCES[name][1]}\nSHA-256: {SOURCES[name][2]}\n")
    binaries = {}
    for binary in sorted([*(PREFIX / "lib").glob("*.dylib"), *(PREFIX / "lib").glob("*.a")]):
        if not binary.is_symlink():
            binaries[binary.name] = hashlib.sha256(binary.read_bytes()).hexdigest()
    stamp.write_text(json.dumps(binaries, sort_keys=True, indent=2) + "\n")


if platform.system() != "Darwin" or platform.machine() != "arm64":
    raise SystemExit("Pinned dependencies require an Apple silicon Mac running natively")
if ARGUMENTS == ["--prefix"]:
    print(PREFIX)
elif not ARGUMENTS:
    ROOT.mkdir(parents=True, exist_ok=True)
    with (ROOT / "build.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        for name in BUILT:
            build(name)
        manifest = {"architecture": "arm64", "platform": PLATFORM_NAME, "minimum_os": "26.0",
                    "toolchain": TOOLCHAIN,
                    "sources": {name: SOURCES[name] for name in BUILT}, "recipe_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
        (PREFIX / "share/licenses/build-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
else:
    raise SystemExit("usage: build.py [--platform=macos|ios|ios-simulator] [--prefix]")
