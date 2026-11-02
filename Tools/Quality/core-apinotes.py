#!/usr/bin/env python3
import argparse
import difflib
import json
import subprocess
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[2]
MODULE = PROJECT / "Sources/CBridge/ChiakiCore"
HEADER = MODULE / "core.hpp"
NOTES = MODULE / "ChiakiCore.apinotes"
INCLUDE = PROJECT / "lib/chiaki-ng-core/include"
ROOT = "libchiaking"


class Scope:
    def __init__(self):
        self.namespaces = {}
        self.records = {}
        self.enums = set()

    def empty(self):
        return not self.enums and all(child.empty() for child in self.children())

    def children(self):
        return [*self.namespaces.values(), *self.records.values()]

    def count(self):
        return len(self.enums) + sum(child.count() for child in self.children())

    def read(self, node):
        for child in node.get("inner", []):
            kind = child.get("kind")
            name = child.get("name")
            if not name:
                continue
            if kind == "NamespaceDecl":
                self.namespaces.setdefault(name, Scope()).read(child)
            elif kind == "CXXRecordDecl" and "inner" in child:
                self.records.setdefault(name, Scope()).read(child)
            elif kind == "EnumDecl" and "inner" in child:
                self.enums.add(name)

    def write(self, depth, lines):
        pad = "  " * depth
        namespaces = {name: scope for name, scope in self.namespaces.items() if not scope.empty()}
        records = {name: scope for name, scope in self.records.items() if not scope.empty()}
        if namespaces:
            lines.append(f"{pad}Namespaces:")
            for name in sorted(namespaces):
                lines.append(f"{pad}- Name: {name}")
                namespaces[name].write(depth + 1, lines)
        if records or self.enums:
            lines.append(f"{pad}Tags:")
            for name in sorted({*records, *self.enums}):
                lines.append(f"{pad}- Name: {name}")
                if name in self.enums:
                    lines.append(f"{pad}  EnumExtensibility: closed")
                if name in records:
                    records[name].write(depth + 1, lines)


def syntax_trees():
    dumped = subprocess.run(
        [
            "xcrun", "clang++", "-x", "c++-header", "-std=gnu++2b", "-fsyntax-only",
            "-Wno-pragma-once-outside-header", "-I", str(INCLUDE),
            "-Xclang", "-ast-dump=json", "-Xclang", f"-ast-dump-filter={ROOT}", str(HEADER),
        ],
        check=True, capture_output=True, text=True,
    ).stdout
    decoder = json.JSONDecoder()
    position = dumped.find("{")
    while position >= 0:
        tree, end = decoder.raw_decode(dumped, position)
        yield tree
        position = dumped.find("{", end)


def generated():
    core = Scope()
    for tree in syntax_trees():
        if tree.get("kind") == "NamespaceDecl" and tree.get("name") == ROOT:
            core.read(tree)
    if core.empty():
        sys.exit(f"No enum found under {ROOT} in {HEADER}")
    lines = ["---", "Name: ChiakiCore", "Namespaces:", f"- Name: {ROOT}"]
    core.write(1, lines)
    return "\n".join(lines) + "\n", core.count()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    arguments = parser.parse_args()
    notes, count = generated()
    if not arguments.check:
        NOTES.write_text(notes)
        print(f"Wrote {count} closed enums to {NOTES.relative_to(PROJECT)}")
        return
    current = NOTES.read_text() if NOTES.exists() else ""
    if current == notes:
        print(f"{NOTES.relative_to(PROJECT)} matches the {count} enums in the pinned core headers")
        return
    sys.stdout.writelines(
        difflib.unified_diff(
            current.splitlines(keepends=True), notes.splitlines(keepends=True),
            "checked in", "from the pinned core headers",
        )
    )
    sys.exit(
        f"{NOTES.relative_to(PROJECT)} does not match the pinned core headers. "
        "Run: make core-notes"
    )


if __name__ == "__main__":
    main()
