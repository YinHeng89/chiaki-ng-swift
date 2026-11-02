#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
mode="${1:-all}"
if [[ "$mode" == all || "$mode" == c || "$mode" == check-c ]]; then
    if ! command -v clang-format >/dev/null; then
        print -u2 'clang-format is required. Install it with: brew install clang-format'
        exit 1
    fi
    c_files=(Sources/**/*.(c|h|m|mm|hpp)(N) lib/bridge/**/*.(c|h|cpp|hpp)(N) Tests/**/*.(c|h|m|cpp|hpp)(N) Tools/**/*.(c|h|m)(N))
    if [[ "$mode" == check-c ]]; then
        clang-format --dry-run --Werror "${c_files[@]}"
    else
        clang-format -i "${c_files[@]}"
    fi
fi
if [[ "$mode" == all || "$mode" == swift ]]; then
    if ! command -v swiftformat >/dev/null; then
        print -u2 'SwiftFormat is required. Install it with: brew install swiftformat'
        exit 1
    fi
    swift_files=(Assets/**/*.swift Sources/**/*.swift Tests/**/*.swift)
    xcrun swiftc -frontend -parse "${swift_files[@]}"
    swiftformat Assets Sources Tests --config .swiftformat
    xcrun swiftc -frontend -parse "${swift_files[@]}"
fi
if [[ "$mode" != all && "$mode" != c && "$mode" != check-c && "$mode" != swift ]]; then
    print -u2 'usage: Scripts/format.sh [all|c|check-c|swift]'
    exit 2
fi
