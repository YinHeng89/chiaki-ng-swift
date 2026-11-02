#!/bin/zsh
set -eu
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
platform="${CHIAKI_PLATFORM:-ios-simulator}"
configuration="${CONFIGURATION:-debug}"
swift_command="${SWIFT:-swift}"
case "$platform" in
    ios)
        sdk_name=iphoneos
        triple=arm64-apple-ios
        ;;
    ios-simulator)
        sdk_name=iphonesimulator
        triple=arm64-apple-ios-simulator
        ;;
    *)
        echo 'CHIAKI_PLATFORM must be ios or ios-simulator' >&2
        exit 1
        ;;
esac
case "$configuration" in
    debug|release) ;;
    *) echo 'CONFIGURATION must be debug or release' >&2; exit 1 ;;
esac
export CHIAKI_PLATFORM="$platform"
if [[ "${CHIAKI_SKIP_CORE:-0}" != 1 ]]; then
    "$project_dir/Scripts/build-core.sh"
fi
sdk_path="$(xcrun --sdk "$sdk_name" --show-sdk-path)"
build=("$swift_command" build --package-path "$project_dir" --scratch-path "$project_dir/.build/$platform" \
    --configuration "$configuration" --triple "$triple" --sdk "$sdk_path")
if (( $# == 0 )); then
    "${build[@]}"
fi
for target in "$@"; do
    "${build[@]}" --target "$target"
done
