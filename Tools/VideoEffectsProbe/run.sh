#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h:h}"
build_dir="$project_dir/.build/video-effects-probe"
mkdir -p "$build_dir"
xcrun clang -fobjc-arc -fmodules -mmacosx-version-min=26.0 \
  -Wall -Wextra -Werror -Wno-unused-parameter -Wno-deprecated-declarations \
  -I "$project_dir/Sources/Video" \
  "$project_dir/Tools/VideoEffectsProbe/main.m" \
  "$project_dir/Sources/Video/FrameInterpolationClient.m" \
  -framework Foundation -framework CoreMedia -framework CoreVideo \
  -framework VideoToolbox -framework IOSurface -framework Metal \
  -o "$build_dir/video-effects-probe"
"$build_dir/video-effects-probe" \
  "$project_dir/Assets/Video/VideoColour.txt"
