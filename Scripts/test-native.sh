#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"

test_video() {
    cd "$project_dir"
    mkdir -p .build/native-video-probe
    xcrun clang -std=c17 -Wall -Wextra -Werror -I Sources/Video \
        Tests/Native/NativeVideoTests/decoder-state.c -o .build/native-video-probe/state-test
    .build/native-video-probe/state-test
    xcrun clang -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter \
        -I Sources/Video/include Sources/Video/VideoDecoderClient.m Sources/Video/AnnexBSample.m \
        Tests/Native/NativeVideoTests/client-contract.m -framework Foundation -framework CoreMedia \
        -framework CoreVideo -framework VideoToolbox -o .build/native-video-probe/client-test
    .build/native-video-probe/client-test
    xcrun clang -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -O2 \
        -I Sources/Video/include Sources/Video/AnnexBSample.m \
        Tests/Native/NativeVideoTests/annexb.m -framework Foundation -framework CoreMedia \
        -o .build/native-video-probe/annexb-test
    .build/native-video-probe/annexb-test
    test_video_slices
    test_video_live_encoded
}

test_video_live_encoded() {
    if ! command -v ffmpeg >/dev/null; then
        print 'SKIP: live H.264, HEVC Main10 and PQ decode needs ffmpeg (make video-deps)'
        return
    fi
    bash "$project_dir/Tools/NativeVideoProbe/run-live-encoded.sh"
}

test_video_slices() {
    local out=.build/native-video-probe
    if ! command -v ffmpeg >/dev/null; then
        print 'SKIP: H.264 multi-slice decode needs ffmpeg (make video-deps)'
        return
    fi
    xcrun clang -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -O2 \
        -I Sources/Video/include Sources/Video/VideoDecoderClient.m Sources/Video/AnnexBSample.m \
        Sources/Video/LiveEncodedVideo.m Tests/Native/NativeVideoTests/multi-slice.m \
        -framework Foundation -framework CoreMedia -framework CoreVideo -framework VideoToolbox \
        -o "$out/multi-slice-test"
    local source=(-hide_banner -loglevel error -y -f lavfi)
    local encode=(-c:v libx264 -profile:v high -pix_fmt yuv420p -preset ultrafast -bf 0 -g 30)
    ffmpeg "${source[@]}" -i testsrc2=size=1920x1080:rate=60 -frames:v 40 "${encode[@]}" \
        -x264-params slices=68:threads=1 -f h264 "$out/rows.h264"
    "$out/multi-slice-test" "$out/rows.h264" 65 1920 1080
    ffmpeg "${source[@]}" -i testsrc2=size=1920x1080:rate=60 -frames:v 40 "${encode[@]}" -b:v 35M \
        -x264-params slice-max-size=1400:aud=1:repeat-headers=1 -f h264 "$out/packetized.h264"
    "$out/multi-slice-test" "$out/packetized.h264" 65 1920 1080
    ffmpeg "${source[@]}" -i testsrc2=size=1280x720:rate=60 -frames:v 20 "${encode[@]}" \
        -x264-params aud=1:repeat-headers=1 -f h264 "$out/resized.h264"
    cat "$out/packetized.h264" "$out/resized.h264" >"$out/switch.h264"
    "$out/multi-slice-test" "$out/switch.h264" 65 1280 720
}

case "${1:-}" in
    video)
        test_video
        ;;
    *)
        print -u2 'usage: Scripts/test-native.sh video'
        exit 2
        ;;
esac
