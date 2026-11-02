#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$project_dir"
probe_dir="$project_dir/.build/video-probe"
mkdir -p "$probe_dir"
python3 "$project_dir/Tools/Dependencies/build.py"
dependency_prefix="$(python3 "$project_dir/Tools/Dependencies/build.py" --prefix)"
export PKG_CONFIG_PATH="$dependency_prefix/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
for package in libavcodec libavformat libavutil; do
    if [[ "$(pkg-config --variable=prefix "$package")" != "$dependency_prefix" ]]; then
        echo "Refusing unpinned probe dependency: $package" >&2
        exit 1
    fi
done
read -r -a compiler_flags <<< "$(pkg-config --cflags libavcodec libavformat libavutil)"
read -r -a library_flags <<< "$(pkg-config --libs libavcodec libavformat libavutil)"
xcrun clang -fobjc-arc -fblocks -Wall -Wextra -Wno-unused-parameter -O2 \
    "${compiler_flags[@]}" Tools/VideoProbe/main.m "${library_flags[@]}" \
    -framework Foundation -framework Metal -framework CoreVideo -framework IOSurface \
    -o "$probe_dir/video-probe"
if [[ -n "${VIDEO_FILE:-}" ]]; then
    "$probe_dir/video-probe" "$VIDEO_FILE" Tools/VideoProbe/colour.metal 0
    exit 0
fi
ffmpeg -hide_banner -loglevel error -y -f lavfi -i 'testsrc2=size=640x360:rate=60' \
    -frames:v 60 -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p -x264-params colorprim=bt709:transfer=bt709:colormatrix=bt709 \
    -color_primaries bt709 -color_trc bt709 -colorspace bt709 "$probe_dir/h264.mp4"
ffmpeg -hide_banner -loglevel error -y -f lavfi -i 'testsrc2=size=640x360:rate=60' \
    -frames:v 60 -c:v libx265 -preset ultrafast -pix_fmt yuv420p10le \
    -x265-params 'log-level=error:pools=1:frame-threads=1:colorprim=bt709:transfer=bt709:colormatrix=bt709' \
    -color_primaries bt709 -color_trc bt709 -colorspace bt709 "$probe_dir/hevc10.mp4"
"$probe_dir/video-probe" "$probe_dir/h264.mp4" Tools/VideoProbe/colour.metal
"$probe_dir/video-probe" "$probe_dir/hevc10.mp4" Tools/VideoProbe/colour.metal

ffmpeg -hide_banner -loglevel error -y -f lavfi \
    -i 'nullsrc=size=640x360:rate=60,format=yuv420p10le,geq=lum=64+876*X/W:cb=512:cr=512' \
    -frames:v 60 -c:v libx265 -preset ultrafast -pix_fmt yuv420p10le \
    -x265-params 'log-level=error:pools=1:frame-threads=1:colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc' \
    -color_primaries bt2020 -color_trc smpte2084 -colorspace bt2020nc "$probe_dir/pq-ramp.mp4"
"$probe_dir/video-probe" "$probe_dir/pq-ramp.mp4" Tools/VideoProbe/colour.metal
xcrun clang -fobjc-arc -fblocks -Wall -Wextra -O2 Tools/VideoProbe/colour-test.m \
    -framework Foundation -framework Metal -o "$probe_dir/colour-test"
"$probe_dir/colour-test" Tools/VideoProbe/colour.metal
