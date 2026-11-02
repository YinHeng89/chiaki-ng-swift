#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$project_dir"
output="$project_dir/.build/live-encoded-probe"
mkdir -p "$output"
xcrun clang -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -O2 \
    -I Sources/Video/include \
    Sources/Video/VideoDecoderClient.m \
    Sources/Video/AnnexBSample.m \
    Sources/Video/LiveEncodedVideo.m \
    Tests/Native/NativeVideoTests/live-encoded.m \
    -framework Foundation -framework CoreMedia -framework CoreVideo -framework VideoToolbox \
    -framework IOSurface -o "$output/live-encoded-test"
ffmpeg -hide_banner -loglevel error -y -f lavfi -i 'testsrc2=size=320x180:rate=60' \
    -frames:v 1 -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p -f h264 "$output/frame.h264"
ffmpeg -hide_banner -loglevel error -y -i "$output/frame.h264" -frames:v 1 -pix_fmt yuv420p -f rawvideo "$output/frame-h264.yuv"
"$output/live-encoded-test" "$output/frame.h264" "$output/frame-h264.yuv" 0
ffmpeg -hide_banner -loglevel error -y -f lavfi -i 'testsrc2=size=320x180:rate=60' \
    -frames:v 1 -c:v libx265 -preset ultrafast -tune zerolatency -pix_fmt yuv420p10le \
    -x265-params 'log-level=error:pools=1:frame-threads=1' -f hevc "$output/frame.hevc"
ffmpeg -hide_banner -loglevel error -y -i "$output/frame.hevc" -frames:v 1 -pix_fmt yuv420p10le -f rawvideo "$output/frame-hevc.yuv"
"$output/live-encoded-test" "$output/frame.hevc" "$output/frame-hevc.yuv" 1
ffmpeg -hide_banner -loglevel error -y -f lavfi -i 'testsrc2=size=320x180:rate=60' \
    -frames:v 1 -c:v libx265 -preset ultrafast -tune zerolatency -pix_fmt yuv420p10le -profile:v main10 \
    -x265-params 'log-level=error:pools=1:frame-threads=1:colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc:hdr10=1' \
    -f hevc "$output/frame-pq.hevc"
ffmpeg -hide_banner -loglevel error -y -i "$output/frame-pq.hevc" -frames:v 1 -pix_fmt yuv420p10le -f rawvideo "$output/frame-pq.yuv"
"$output/live-encoded-test" "$output/frame-pq.hevc" "$output/frame-pq.yuv" 2
