#!/usr/bin/env python3
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from collections import defaultdict
from pathlib import Path
from urllib.parse import unquote, urlparse

PROJECT = Path(__file__).resolve().parents[2]
OWNED = [PROJECT / "Sources", PROJECT / "Assets", PROJECT / "Tests" / "ChiakiTestSupport"]
RETIRING_TARGETS = set()
WITNESS_NAMES = {"body"}
EXEMPT_ACCESS = {"private", "fileprivate"}
SWIFT = os.environ.get("SWIFT", "swift")
PYTHON = os.environ.get("PYTHON", sys.executable)


class DocsLint:
    def __init__(self, arguments):
        self.arguments = arguments
        self.failures = 0
        self.sources = {}

    def run(self):
        targets = self.targets()
        graphs = self.symbol_graphs(targets)
        self.check_comments(targets, graphs)
        if not self.arguments.skip_docc:
            self.check_catalogs(targets, graphs)
        if not self.arguments.skip_core:
            self.check_core()
        if self.failures:
            print(f"lint-docs: {self.failures} problem(s)", file=sys.stderr)
            return 1
        print("lint-docs: ok")
        return 0

    def fail(self, message):
        print(message, file=sys.stderr)
        self.failures += 1

    def targets(self):
        description = json.loads(
            subprocess.run(
                [SWIFT, "package", "describe", "--type", "json"],
                cwd=PROJECT,
                check=True,
                capture_output=True,
                text=True,
            ).stdout
        )
        selected = {}
        for target in description["targets"]:
            if target["type"] not in ("library", "executable"):
                continue
            if target.get("module_type") != "SwiftTarget":
                continue
            path = (PROJECT / target["path"]).resolve()
            if not any(path.is_relative_to(root) for root in OWNED):
                continue
            if not list(path.rglob("*.swift")):
                continue
            if target["name"] in RETIRING_TARGETS:
                continue
            if self.arguments.target and target["name"] not in self.arguments.target:
                continue
            selected[target["name"]] = path
        return selected

    def symbol_graphs(self, targets):
        if not self.arguments.skip_build:
            subprocess.run(
                [
                    SWIFT,
                    "package",
                    "dump-symbol-graph",
                    "--minimum-access-level",
                    "internal",
                    "--skip-synthesized-members",
                ],
                cwd=PROJECT,
                check=True,
                stdout=subprocess.DEVNULL,
            )
        directories = sorted(
            (PROJECT / ".build").glob("*/symbolgraph"),
            key=lambda directory: directory.stat().st_mtime,
        )
        graphs = defaultdict(list)
        for module in targets:
            candidates = [*directories[-1:]] if directories else []
            candidates += sorted(
                (PROJECT / ".build").glob(f"out/Products/*/*/{module}.symbolgraphs"),
                key=lambda directory: directory.stat().st_mtime,
            )[-1:]
            if not candidates:
                raise SystemExit("lint-docs: no symbol graphs under .build")
            for directory in candidates:
                found = sorted(
                    [*directory.glob(f"{module}.symbols.json"), *directory.glob(f"{module}@*.symbols.json")]
                )
                if found:
                    graphs[module] = found
            if not graphs[module]:
                self.fail(f"{module}: no symbol graph was produced")
        return graphs

    def check_comments(self, targets, graphs):
        for module, files in graphs.items():
            root = targets[module]
            missing = []
            for file in files:
                for symbol in json.loads(file.read_text())["symbols"]:
                    location = self.location(symbol, root)
                    if location and self.undocumented(symbol):
                        missing.append((location, symbol))
            for (path, line), symbol in sorted(missing, key=lambda item: item[0]):
                kind = symbol["kind"]["displayName"].lower()
                title = ".".join(symbol["pathComponents"])
                self.fail(f"{path.relative_to(PROJECT)}:{line}: undocumented {kind} {title}")

    def location(self, symbol, root):
        location = symbol.get("location")
        if not location:
            return None
        path = Path(unquote(urlparse(location["uri"]).path)).resolve()
        if not path.is_relative_to(root):
            return None
        line = location["position"]["line"]
        if not self.spelled(symbol, self.source(path)[line]):
            return None
        return path, line + 1

    def source(self, path):
        if path not in self.sources:
            self.sources[path] = path.read_text().splitlines()
        return self.sources[path]

    def spelled(self, symbol, text):
        if symbol["kind"]["identifier"] == "swift.init":
            return "init" in text
        name = symbol["pathComponents"][-1].split("(")[0]
        return name in text

    def undocumented(self, symbol):
        if symbol["accessLevel"] in EXEMPT_ACCESS:
            return False
        if symbol["kind"]["identifier"] == "swift.extension":
            return False
        if symbol["pathComponents"][-1] in WITNESS_NAMES:
            return False
        comment = symbol.get("docComment", {}).get("lines", [])
        return not any(line["text"].strip() for line in comment)

    def check_catalogs(self, targets, graphs):
        docc = subprocess.run(
            ["xcrun", "--find", "docc"], check=True, capture_output=True, text=True
        ).stdout.strip()
        for module, root in targets.items():
            catalog = root / f"{module}.docc"
            if not catalog.is_dir():
                self.fail(f"{root.relative_to(PROJECT)}: no {module}.docc catalog")
                continue
            with tempfile.TemporaryDirectory() as scratch:
                symbols = Path(scratch) / "symbols"
                symbols.mkdir()
                for file in graphs[module]:
                    shutil.copy(file, symbols / file.name)
                result = subprocess.run(
                    [
                        docc,
                        "convert",
                        str(catalog),
                        "--additional-symbol-graph-dir",
                        str(symbols),
                        "--output-path",
                        str(Path(scratch) / "out"),
                        "--fallback-display-name",
                        module,
                        "--fallback-bundle-identifier",
                        f"chiaki-ng.{module}",
                        "--warnings-as-errors",
                        "--ide-console-output",
                    ],
                    capture_output=True,
                    text=True,
                )
            if result.returncode:
                for line in (result.stdout + result.stderr).splitlines():
                    if "warning:" in line or "error:" in line:
                        print(line, file=sys.stderr)
                self.fail(f"{catalog.relative_to(PROJECT)}: docc convert failed")

    def check_core(self):
        result = subprocess.run([PYTHON, "lib/chiaki-ng-core/tools/docs/docs.py", "lint"], cwd=PROJECT)
        if result.returncode:
            self.fail("lib/chiaki-ng-core: docs.py lint failed")


def main():
    parser = argparse.ArgumentParser(description="Check DocC coverage and catalogs")
    parser.add_argument("target", nargs="*")
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--skip-docc", action="store_true")
    parser.add_argument("--skip-core", action="store_true")
    return DocsLint(parser.parse_args()).run()


if __name__ == "__main__":
    sys.exit(main())
