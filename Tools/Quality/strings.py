#!/usr/bin/env python3
import json
import re
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[2]
SOURCES = PROJECT / "Sources"
SEGMENT = r"[a-z]+(?:[A-Z][a-z]*)*[0-9]*"
KEY = re.compile(rf"^{SEGMENT}(?:\.{SEGMENT})*$")
SPECIFIER = re.compile(r"%(?:\(([a-z][A-Za-z]*)\))?(?:\d+\$)?[-+ 0#]*\d*(?:\.\d+)?(?:ll|l|h)?[@dDiuUxXoOfFeEgGcCsSp%]")


class StringsLint:
    def __init__(self):
        self.failures = []

    @staticmethod
    def symbol(key):
        head, *rest = key.split(".")
        return head + "".join(part[0].upper() + part[1:] for part in rest)

    @staticmethod
    def values(entry, language):
        localization = entry.get("localizations", {}).get(language, {})
        if "stringUnit" in localization:
            return [localization["stringUnit"].get("value", "")]
        plural = localization.get("variations", {}).get("plural", {})
        forms = sorted(plural, key=lambda form: form == "other")
        return [plural[form].get("stringUnit", {}).get("value", "") for form in forms]

    @staticmethod
    def arguments(values):
        return [set(SPECIFIER.findall(value)) - {""} for value in values]

    def fail(self, message):
        self.failures.append(message)

    def used_symbols(self, target):
        words = set()
        for source in (SOURCES / target).rglob("*.swift"):
            words.update(re.findall(r"\.([a-z][A-Za-z0-9]*)\b", source.read_text(encoding="utf-8")))
        return words

    def check(self, path):
        where = path.relative_to(PROJECT)
        strings = json.loads(path.read_text(encoding="utf-8"))["strings"]
        used = self.used_symbols(path.parent.parent.name)
        seen = {}
        for key, entry in strings.items():
            symbol = self.symbol(key)
            if not KEY.match(key):
                self.fail(f"{where}: {key} is not dotted lowerCamel, such as settings.picture.resolution")
            if symbol in seen:
                self.fail(f"{where}: {key} and {seen[symbol]} generate the same symbol")
            seen[symbol] = key
            if entry.get("extractionState") != "manual":
                self.fail(f"{where}: {key} must be a manual entry")
            english = self.values(entry, "en")
            if not english or not all(english):
                self.fail(f"{where}: {key} has no English value")
                continue
            expected = self.arguments(english)[-1]
            if any(not shape <= expected for shape in self.arguments(english)):
                self.fail(f"{where}: {key} has a plural form with an argument its other form lacks")
            for language in entry.get("localizations", {}):
                if language != "en" and self.arguments(self.values(entry, language))[-1:] != [expected]:
                    self.fail(f"{where}: {key} in {language} does not use the same arguments as English")
            if symbol not in used:
                self.fail(f"{where}: {key} is never used as .{symbol}")

    def run(self):
        for path in sorted(SOURCES.glob("*/Resources/Localizable.xcstrings")):
            self.check(path)
        for stray in sorted(SOURCES.glob("*/Resources/*.xcstrings")):
            if stray.name != "Localizable.xcstrings":
                self.fail(f"{stray.relative_to(PROJECT)}: each module keeps its strings in Localizable.xcstrings")
        for failure in self.failures:
            print(failure, file=sys.stderr)
        return 1 if self.failures else 0


if __name__ == "__main__":
    sys.exit(StringsLint().run())
