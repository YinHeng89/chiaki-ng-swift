#!/usr/bin/env python3
"""Summarises stream round-trip times from the chiaki-ng logs.

Reads the core's `round_trip` lines, keeps the last line of each stream (its sample count
and the percentiles of its latest samples), and prints one row per stream and the
averages. To compare two builds or setups, run it once per time window with --since and
--until (UTC, as the logs write it).

Usage: Scripts/compare-round-trip.py [--since 2026-10-30T12:00] [--until ...] [--min-samples 60] [log ...]
"""

import argparse
import glob
import os
import re
import statistics

LINE = re.compile(r"^(?P<time>\S+) .* (?P<link>\S+) round_trip (?P<values>.*)$")
VALUE = re.compile(r"(\w+)=(\d+)")
KEYS = {
    "samples": "samples", "median": "median_us", "p90": "p90_us", "p99": "p99_us", "max": "max_us",
    "smoothed": "smoothed_us",
}
FIELDS = ("median", "p90", "p99", "max", "smoothed")


def parsed(line):
    """Returns a round_trip line's time, link and values, or None."""
    match = LINE.match(line)
    if not match:
        return None
    values = dict(VALUE.findall(match["values"]))
    if any(key not in values for key in KEYS.values()):
        return None
    run = {name: values[key] for name, key in KEYS.items()}
    run.update(time=match["time"], link=match["link"])
    return run


def streams(paths):
    """Returns the last round_trip line of each stream, oldest first, splitting each app's log folder on its own."""
    folders = {}
    for path in paths:
        with open(path, errors="replace") as log:
            folders.setdefault(os.path.dirname(path), []).extend(filter(None, map(parsed, log)))
    ends = []
    for lines in folders.values():
        lines.sort(key=lambda run: run["time"])
        last = None
        for run in lines:
            if last and (int(run["samples"]) < int(last["samples"]) or run["link"] != last["link"]):
                ends.append(last)
            last = run
        if last:
            ends.append(last)
    return sorted(ends, key=lambda run: run["time"])


def milliseconds(value):
    return f"{int(value) / 1000:7.2f}"


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("logs", nargs="*")
    parser.add_argument("--since", default="", help="ignore streams that ended before this UTC ISO time")
    parser.add_argument("--until", default="~", help="ignore streams that ended after this UTC ISO time")
    parser.add_argument("--min-samples", type=int, default=60, help="ignore streams with fewer samples (a few a second)")
    options = parser.parse_args()
    paths = options.logs or glob.glob(os.path.expanduser("~/Library/Logs/io.github.chiaki-ng.chiaki-ng*/chiaki*.log"))

    kept = [run for run in streams(paths) if options.since <= run["time"] <= options.until]
    kept = [run for run in kept if int(run["samples"]) >= options.min_samples]
    if not kept:
        print("No streams with round_trip lines found in that window.")
        return

    print("ended                      link     samples  median_ms   p90_ms   p99_ms   max_ms  smoothed_ms")
    for run in kept:
        print(
            f"{run['time'][:26]:26} {run['link']:8} {run['samples']:>7}  "
            + "  ".join(milliseconds(run[field]) for field in FIELDS)
        )

    means = "  ".join(f"{name}={statistics.mean(int(run[name]) for run in kept) / 1000:.2f}" for name in FIELDS)
    print(f"\naverage over {len(kept)} streams (ms): {means}")


if __name__ == "__main__":
    main()
