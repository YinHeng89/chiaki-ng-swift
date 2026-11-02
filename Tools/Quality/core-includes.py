#!/usr/bin/env python3
import argparse
import re
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[2]
ROOTS = ["Sources", "lib", "Tests", "Tools", "Scripts"]
EXCLUDED = [PROJECT / "lib" / "chiaki-ng-core"]
TEST_ROOTS = [PROJECT / "Tests"]
EXTENSIONS = {".c", ".cc", ".cpp", ".cxx", ".h", ".hh", ".hpp", ".hxx", ".m", ".mm", ".inl"}
DOMAINS = ["users", "consoles", "catalog", "trophies", "play", "kakusan", "messages"]
FACES = {
    "libchiaking/chiaki_ng.hpp",
    "libchiaking/version.hpp",
    "libchiaking/platform/platform.hpp",
    "libchiaking/platform/defaults.hpp",
    "libchiaking/platform/stock_providers.hpp",
    *(f"libchiaking/{domain}.hpp" for domain in DOMAINS),
    *(f"libchiaking/{domain}_types.hpp" for domain in DOMAINS),
}
TESTING = "libchiaking/testing/"
DIRECTIVE = re.compile(r'^\s*#\s*(?:include|import)\s*[<"](libchiaking/[^>"]+)[>"]')


class CoreIncludes:
    def __init__(self, roots):
        self.roots = roots

    def run(self):
        offences = [offence for path in self.sources() for offence in self.offences(path)]
        for offence in offences:
            print(offence, file=sys.stderr)
        if offences:
            print(f"core-includes: {len(offences)} include(s) outside the core's public faces", file=sys.stderr)
            return 1
        print("core-includes: ok")
        return 0

    def sources(self):
        for root in self.roots:
            if root.is_file():
                yield root
                continue
            for path in sorted(root.rglob("*")):
                if path.suffix in EXTENSIONS and path.is_file() and not self.excluded(path):
                    yield path

    @staticmethod
    def excluded(path):
        return any(path.is_relative_to(folder) for folder in EXCLUDED) or ".build" in path.parts

    @staticmethod
    def allowed(header, path):
        if header in FACES:
            return True
        is_test = any(path.is_relative_to(folder) for folder in TEST_ROOTS)
        return is_test and header.startswith(TESTING)

    def offences(self, path):
        text = path.read_text(encoding="utf-8", errors="replace")
        for number, line in enumerate(text.splitlines(), start=1):
            match = DIRECTIVE.match(line)
            if match and not self.allowed(match.group(1), path.resolve()):
                yield f"{path.relative_to(PROJECT)}:{number}: {match.group(1)}"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="*", type=Path)
    arguments = parser.parse_args()
    roots = [path.resolve() for path in arguments.paths] or [PROJECT / root for root in ROOTS]
    return CoreIncludes([root for root in roots if root.exists()]).run()


if __name__ == "__main__":
    sys.exit(main())
