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
app="${CHIAKI_APP:-$project_dir/.build/chiaki-ng.app}"
version_tag="$(/usr/libexec/PlistBuddy -c 'Print :ChiakiVersionTag' "$app/Contents/Info.plist" 2>/dev/null || true)"
commit="$(/usr/libexec/PlistBuddy -c 'Print :ChiakiCommit' "$app/Contents/Info.plist" 2>/dev/null || true)"
artifact_name="${CHIAKI_ARTIFACT_NAME:-chiaki-ng-v2.0.0${version_tag:+-$version_tag}${commit:+-$commit}-arm64-macOS26}"
archive="$project_dir/dist/$artifact_name.dmg"

if [[ -z "$identity" || -z "$notary_profile" ]]; then
    echo 'Set the Developer ID identity and notary profile in .local-signing or the environment.' >&2
    exit 1
fi
xcrun stapler validate "$app"
if [[ -e "$archive" ]]; then
    echo "Refusing to replace existing artifact: $archive" >&2
    exit 1
fi

work_dir="$(mktemp -d "$project_dir/.build/dmg.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
staging="$work_dir/staging"
mkdir -p "$staging" "$project_dir/dist"
ditto "$app" "$staging/chiaki-ng.app"
swift "$project_dir/Tools/Packaging/dmg-background.swift" "$work_dir" ${version_tag:+"$version_tag"}
tiffutil -cathidpicheck "$work_dir/dmg-background.png" "$work_dir/dmg-background@2x.png" \
    -out "$work_dir/dmg-background.tiff"
create-dmg \
    --volname "chiaki-ng" \
    --volicon "$app/Contents/Resources/AppIcon.icns" \
    --background "$work_dir/dmg-background.tiff" \
    --window-pos 200 120 \
    --window-size 660 400 \
    --icon-size 128 \
    --text-size 13 \
    --icon "chiaki-ng.app" 180 190 \
    --hide-extension "chiaki-ng.app" \
    --app-drop-link 480 190 \
    --no-internet-enable \
    "$archive" \
    "$staging"
codesign --force --timestamp --sign "$identity" "$archive"
xcrun notarytool submit "$archive" --keychain-profile "$notary_profile" --wait
xcrun stapler staple "$archive"
xcrun stapler validate "$archive"
spctl --assess --type open --context context:primary-signature --verbose=2 "$archive"
shasum -a 256 "$archive"
echo "$archive"
