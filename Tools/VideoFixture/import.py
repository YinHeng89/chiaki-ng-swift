#!/usr/bin/env python3
"""Import a short public YouTube PQ/HDR fixture. Never part of live playback."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[2]

def inspect(path):
    result = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0",
        "-show_streams", "-of", "json", str(path)], check=True, capture_output=True, text=True)
    streams = json.loads(result.stdout).get("streams", [])
    if len(streams) != 1:
        raise ValueError("Expected one selected video stream")
    stream = streams[0]

    if stream.get("color_transfer") != "smpte2084":
        raise ValueError("Sample is not PQ HDR (SDR, HLG and untagged input are rejected)")
    if stream.get("color_primaries") != "bt2020" or stream.get("color_space") != "bt2020nc":
        raise ValueError("Expected BT.2020 primaries and non-constant-luminance matrix")
    if stream.get("pix_fmt") not in ("yuv420p10le", "yuv420p12le", "p010le", "p012le"):
        raise ValueError("Expected 10/12-bit 4:2:0 HDR input")
    if not (0 < stream.get("width", 0) <= 4096 and 0 < stream.get("height", 0) <= 2160):
        raise ValueError("Fixture exceeds the 4K diagnostic budget")
    return stream

def main():
    url = os.environ.get("VIDEO_URL", "")
    parsed = urlparse(url)
    if parsed.scheme != "https" or parsed.hostname not in ("youtube.com", "www.youtube.com", "youtu.be") or parsed.username or parsed.password:
        raise ValueError("Set VIDEO_URL to a public HTTPS YouTube video URL")
    for executable in ("yt-dlp", "ffmpeg", "ffprobe"):
        if not shutil.which(executable):
            raise ValueError(f"Missing {executable}; install the fixture tools with make video-deps")
    directory = ROOT / ".build" / "video-fixtures"
    directory.mkdir(parents=True, exist_ok=True)
    destination = Path(tempfile.mkdtemp(prefix="youtube-", dir=directory))


    subprocess.run(["yt-dlp", "--ignore-config", "--no-playlist", "--no-cache-dir",
        "--socket-timeout", "20", "--retries", "2", "--fragment-retries", "2",
        "--download-sections", "*0-20", "--downloader", "ffmpeg",
        "-f", "bv[dynamic_range^=HDR][height<=2160]",
        "-o", str(destination / "source.%(ext)s"), "--", url], check=True)
    candidates = [p for p in destination.glob("source.*") if p.suffix in (".mp4", ".webm", ".mkv", ".mov")]
    if len(candidates) != 1:
        raise ValueError("Expected one completed source video")
    source = candidates[0]
    original = inspect(source)
    output = destination / "fixture-hevc-pq.mp4"
    converted = original["codec_name"] != "hevc" or original["pix_fmt"] != "yuv420p10le"
    encoding = ["-c:v", "copy"]
    if converted:


        encoding = ["-c:v", "libx265", "-preset", "fast", "-crf", "18", "-pix_fmt", "yuv420p10le",
            "-x265-params", "log-level=error:pools=2:frame-threads=2:colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc",
            "-color_primaries", "bt2020", "-color_trc", "smpte2084", "-colorspace", "bt2020nc"]
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-i", str(source),
        "-map", "0:v:0", "-an", "-t", "20", *encoding, str(output)], check=True)
    prepared = inspect(output)

    (destination / "provenance.json").write_text(json.dumps({
        "source_page": url, "offline_transcode": converted,
        "note": "PQ renderer fixture; transcode may not preserve dynamic/mastering metadata. Original retained.",
        "source_video": original, "prepared_video": prepared}, indent=2))
    print(f"Verified PQ fixture: {output}")
    print("Run: VIDEO_FILE='<fixture path>' make video-probe")

if __name__ == "__main__":
    try:
        main()
    except (ValueError, subprocess.CalledProcessError, json.JSONDecodeError) as error:
        print(f"Fixture import failed: {error}", file=sys.stderr)
        sys.exit(1)
