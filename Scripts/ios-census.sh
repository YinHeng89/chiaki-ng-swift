#!/bin/zsh
set -u
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
scratch="${1:-$project_dir/.build/ios-census}"
sdk_path="$(xcrun --sdk iphonesimulator --show-sdk-path)"
CHIAKI_PLATFORM=ios-simulator swift build --package-path "$project_dir" --build-system native \
    --scratch-path "$scratch" --triple arm64-apple-ios26.0-simulator --sdk "$sdk_path" \
    --target ChiakiNG -Xswiftc -continue-building-after-errors > "$scratch.log" 2>&1
sed 's/\x1b\[[0-9;]*m//g' "$scratch.log" | grep -E '^/.*error:' | cut -c1-300 \
    | sed "s#$project_dir/##" | sort -u > "$scratch.errors"
wc -l < "$scratch.errors"
