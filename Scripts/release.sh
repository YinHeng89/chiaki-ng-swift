#!/bin/zsh
set -eu

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
identity="${CHIAKI_DEVELOPER_IDENTITY:-}"
notary_profile="${CHIAKI_NOTARY_PROFILE:-}"
identity_file="$project_dir/.local-signing/developer-identity"
notary_profile_file="$project_dir/.local-signing/notary-profile"
if [[ -z "$identity" && -f "$identity_file" ]]; then
    identity="$(cat "$identity_file")"
fi
if [[ -z "$notary_profile" && -f "$notary_profile_file" ]]; then
    notary_profile="$(cat "$notary_profile_file")"
fi
version_tag="${CHIAKI_VERSION_TAG:-}"
commit="$(git -C "$project_dir" rev-parse --short HEAD)"
artifact_name="${CHIAKI_ARTIFACT_NAME:-chiaki-ng-v2.0.0${version_tag:+-$version_tag}-$commit-arm64-macOS26}"

if [[ -z "$identity" ]]; then
    echo 'Set CHIAKI_DEVELOPER_IDENTITY or .local-signing/developer-identity to a Developer ID Application identity.' >&2
    exit 1
fi
if [[ -z "$notary_profile" ]]; then
    echo 'Set CHIAKI_NOTARY_PROFILE or .local-signing/notary-profile to a notarytool Keychain profile.' >&2
    exit 1
fi
if ! security find-identity -v -p codesigning | grep -F "Developer ID Application" | grep -Fq "$identity"; then
    echo "Developer ID Application identity not found: $identity" >&2
    exit 1
fi

CHIAKI_CODE_SIGN_IDENTITY="$identity" CHIAKI_LAUNCH_APP=0 CONFIGURATION=release CHIAKI_VERSION_TAG="$version_tag" \
    "$project_dir/Scripts/run-app.sh"

app="$project_dir/.build/chiaki-ng.app"
dist="$project_dir/dist"
work_dir="$(mktemp -d "$project_dir/.build/notarize.XXXXXX")"
submission="$work_dir/$artifact_name-notary.zip"
trap 'rm -rf "$work_dir"' EXIT

find "$app/Contents/Frameworks" -type f -name '*.dylib' -print0 | while IFS= read -r -d '' library; do
    codesign --force --timestamp --options runtime --sign "$identity" "$library"
done
entitlements="$project_dir/Tools/Packaging/ChiakiNG.entitlements"
codesign --force --timestamp --options runtime --entitlements "$entitlements" --sign "$identity" \
    "$app/Contents/MacOS/ChiakiNG"
codesign --force --timestamp --options runtime --entitlements "$entitlements" --sign "$identity" "$app"
codesign --verify --deep --strict --verbose=2 "$app"

mkdir -p "$dist"
ditto -c -k --sequesterRsrc --keepParent "$app" "$submission"
xcrun notarytool submit "$submission" --keychain-profile "$notary_profile" --wait
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"

CHIAKI_APP="$app" CHIAKI_ARTIFACT_NAME="$artifact_name" CHIAKI_DEVELOPER_IDENTITY="$identity" \
    CHIAKI_NOTARY_PROFILE="$notary_profile" "$project_dir/Scripts/package-dmg.sh"
