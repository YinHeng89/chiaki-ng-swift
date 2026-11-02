#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$project_dir"
output="$project_dir/.build/native-video-probe"
mkdir -p "$output"
xcrun clang -std=c17 -Wall -Wextra -Werror -I Sources/Video Tests/Native/NativeVideoTests/decoder-state.c -o "$output/state-test"
"$output/state-test"
xcrun clang -fobjc-arc -fblocks -Wall -Wextra -Wno-unused-parameter -Wno-deprecated-declarations -O2 \
    -I Sources/Video/include -I Sources/Video Sources/Video/VideoDecoderClient.m Sources/Video/AnnexBSample.m Tools/NativeVideoProbe/main.m \
    -framework Foundation -framework AVFoundation -framework VideoToolbox -framework CoreMedia \
    -framework CoreVideo -framework Metal -framework IOSurface -o "$output/native-video-probe"
run_fixture() {
    local fixture_path="$1" expected="$2"
    if [[ "$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_tag_string -of default=noprint_wrappers=1:nokey=1 "$fixture_path")" == hev1 ]]; then
        ffmpeg -hide_banner -loglevel error -y -i "$fixture_path" -map 0:v:0 -c:v copy -tag:v hvc1 "$output/fixture-hvc1.mp4"
        fixture_path="$output/fixture-hvc1.mp4"
    fi
    "$output/native-video-probe" "$fixture_path" Tools/VideoProbe/colour.metal "$expected"
}
if [[ -n "${VIDEO_FILE:-}" ]]; then
    run_fixture "$VIDEO_FILE" 0
else
    for fixture in h264 hevc10 pq-ramp; do
        path="$project_dir/.build/video-probe/$fixture.mp4"
        [[ -f "$path" ]] || { echo 'Run make video-probe to generate fixtures first' >&2; exit 1; }
        run_fixture "$path" 60
    done
fi
