#!/bin/zsh
set -eu

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
signing_dir="$project_dir/.local-signing"
mode="${1:-pkg}"
case "$mode" in
    sandbox|pkg|upload) ;;
    *) echo 'usage: app-store.sh sandbox|pkg|upload' >&2; exit 1 ;;
esac
bundle_id=io.github.chiaki-ng.chiaki-ng.appstore
app="$project_dir/.build/app-store/chiaki-ng.app"

setting() {
    local value="$1" file="$signing_dir/$2"
    if [[ -z "$value" && -f "$file" ]]; then
        value="$(cat "$file")"
    fi
    printf '%s' "$value"
}

find_identity() {
    security find-identity -v -p "$1" | grep -F "$2" | head -1 | awk '{print $2}'
}

if [[ "$mode" == sandbox ]]; then
    identity="$(setting "${CHIAKI_CODE_SIGN_IDENTITY:-}" identity)"
    if [[ -z "$identity" ]]; then
        identity="$(find_identity codesigning 'Apple Development')"
    fi
else
    identity="$(setting "${CHIAKI_APP_STORE_IDENTITY:-}" app-store-identity)"
    if [[ -z "$identity" ]]; then
        identity="$(find_identity codesigning 'Apple Distribution')"
    fi
    installer="$(setting "${CHIAKI_INSTALLER_IDENTITY:-}" app-store-installer-identity)"
    if [[ -z "$installer" ]]; then
        installer="$(find_identity basic '3rd Party Mac Developer Installer')"
    fi
    if [[ -z "$installer" ]]; then
        installer="$(find_identity basic 'Mac Installer Distribution')"
    fi
    if [[ -z "$installer" ]]; then
        echo 'No Mac Installer Distribution identity found; set CHIAKI_INSTALLER_IDENTITY.' >&2
        exit 1
    fi
    profile="${CHIAKI_APP_STORE_PROFILE:-$signing_dir/app-store.provisionprofile}"
    if [[ ! -f "$profile" ]]; then
        echo "No Mac App Store provisioning profile at $profile; set CHIAKI_APP_STORE_PROFILE." >&2
        exit 1
    fi
fi
if [[ -z "$identity" ]]; then
    echo 'No signing identity found for this build.' >&2
    exit 1
fi

CHIAKI_APP_STORE=1 CHIAKI_CODE_SIGN_IDENTITY=- CHIAKI_LAUNCH_APP=0 CONFIGURATION=release \
    CHIAKI_VERSION_TAG="${CHIAKI_VERSION_TAG:-}" "$project_dir/Scripts/run-app.sh"

work_dir="$(mktemp -d "$project_dir/.build/app-store/sign.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
entitlements="$work_dir/ChiakiNG.entitlements"
cp "$project_dir/Tools/Packaging/ChiakiNG-AppStore.entitlements" "$entitlements"
if [[ "$mode" != sandbox ]]; then
    security cms -D -i "$profile" > "$work_dir/profile.plist"
    application_id="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' \
        "$work_dir/profile.plist")"
    team_id="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.team-identifier' \
        "$work_dir/profile.plist")"
    if [[ "$application_id" != "$team_id.$bundle_id" ]]; then
        echo "The provisioning profile is for $application_id, not $team_id.$bundle_id." >&2
        exit 1
    fi
    /usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $application_id" \
        -c "Add :com.apple.developer.team-identifier string $team_id" "$entitlements"
    cp -X "$profile" "$app/Contents/embedded.provisionprofile"
fi
xattr -dr com.apple.quarantine "$app"
if [[ -n "$(xattr -lr "$app" | grep -F com.apple.quarantine)" ]]; then
    echo 'A file in the app is still marked com.apple.quarantine, which App Store Connect refuses.' >&2
    exit 1
fi

find "$app/Contents/Frameworks" -type f -name '*.dylib' -print0 | while IFS= read -r -d '' library; do
    codesign --force --timestamp --options runtime --sign "$identity" "$library"
done
codesign --force --timestamp --options runtime --entitlements "$entitlements" --sign "$identity" \
    --identifier "$bundle_id" "$app/Contents/MacOS/ChiakiNG"
codesign --force --timestamp --options runtime --entitlements "$entitlements" --sign "$identity" \
    --identifier "$bundle_id" "$app"
codesign --verify --deep --strict --verbose=2 "$app"
if ! codesign -d --entitlements - --xml "$app" 2>/dev/null | grep -q 'com.apple.security.app-sandbox'; then
    echo 'The signed app is not sandboxed.' >&2
    exit 1
fi
if [[ "$mode" == sandbox ]]; then
    printf 'Built the sandboxed app %s\n' "$app"
    exit 0
fi

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")"
mkdir -p "$project_dir/dist"
package="$project_dir/dist/chiaki-ng-$version-$build-AppStore.pkg"
productbuild --component "$app" /Applications --sign "$installer" "$package"
pkgutil --check-signature "$package"
printf 'Built %s\n' "$package"
if [[ "$mode" != upload ]]; then
    exit 0
fi

key_files=("$signing_dir"/AuthKey_*.p8(N))
key_id="${CHIAKI_API_KEY_ID:-}"
if [[ -z "$key_id" && ${#key_files} == 1 ]]; then
    key_id="${${key_files[1]:t:r}#AuthKey_}"
fi
issuer="$(setting "${CHIAKI_API_ISSUER:-}" app-store-issuer)"
if [[ -z "$key_id" || -z "$issuer" ]]; then
    echo 'Set CHIAKI_API_KEY_ID and CHIAKI_API_ISSUER, or put one AuthKey_<id>.p8 and app-store-issuer in .local-signing.' >&2
    exit 1
fi
export API_PRIVATE_KEYS_DIR="$signing_dir"
xcrun altool --validate-app "$package" --platform macos --api-key "$key_id" --api-issuer "$issuer"
xcrun altool --upload-package "$package" --platform macos --api-key "$key_id" --api-issuer "$issuer"
