#!/bin/zsh
set -eu
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
configuration="${CONFIGURATION:-debug}"
swift_command="${SWIFT:-swift}"
platform="${CHIAKI_PLATFORM:-ios-simulator}"
bundle_id="${IOS_BUNDLE_ID:-io.github.chiaki-ng.chiaki-ng}"
case "$platform" in
    ios)
        sdk_name=iphoneos
        triple=arm64-apple-ios
        supported_platform=iPhoneOS
        core_dir="$project_dir/.build/native-core-ios"
        device="${IOS_DEVICE:-}"
        ;;
    ios-simulator)
        sdk_name=iphonesimulator
        triple=arm64-apple-ios-simulator
        supported_platform=iPhoneSimulator
        core_dir="$project_dir/.build/native-core-ios-simulator"
        device="${IOS_DEVICE:-booted}"
        ;;
    *)
        echo 'CHIAKI_PLATFORM must be ios or ios-simulator' >&2
        exit 1
        ;;
esac
export CHIAKI_PLATFORM="$platform"
"$project_dir/Scripts/build-ios.sh"
sdk_path="$(xcrun --sdk "$sdk_name" --show-sdk-path)"
bin_dir="$("$swift_command" build --package-path "$project_dir" --scratch-path "$project_dir/.build/$platform" \
    --configuration "$configuration" --triple "$triple" --sdk "$sdk_path" --show-bin-path)"
app_dir="$project_dir/.build/$platform/chiaki-ng.app"
rm -rf "$app_dir"
mkdir -p "$app_dir/Frameworks"
dependency_prefix="$(python3 "$project_dir/Tools/Dependencies/build.py" "--platform=$platform" --prefix)"
ditto "$dependency_prefix/share/licenses" "$app_dir/Licenses"
cp "$core_dir/libChiakiRegistration.dylib" "$core_dir/libChiakiInput.dylib" "$core_dir/libSDL3.0.dylib" \
    "$app_dir/Frameworks/"
cp "$bin_dir/ChiakiNG" "$app_dir/ChiakiNG"
icon_source="$project_dir/Assets/Images/Branding/chiaking-color.png"
icon_dir="$project_dir/.build/$platform/app-icon"
if [[ ! -d "$icon_dir" || "$icon_source" -nt "$icon_dir" || "$project_dir/Tools/Packaging/app-icon.swift" -nt "$icon_dir" ]]; then
    rm -rf "$icon_dir"
    swift "$project_dir/Tools/Packaging/app-icon.swift" --ios "$icon_source" "$icon_dir"
fi
cp "$icon_dir"/AppIcon*.png "$app_dir/"
for resource_bundle in "$bin_dir"/*.bundle; do
    ditto "$resource_bundle" "$app_dir/$(basename "$resource_bundle")"
done
cat > "$app_dir/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>chiaki-ng</string>
<key>CFBundleDisplayName</key><string>chiaki-ng</string>
<key>CFBundleIdentifier</key><string>BUNDLE_ID</string>
<key>CFBundleExecutable</key><string>ChiakiNG</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>2.0.0</string>
<key>MinimumOSVersion</key><string>26.0</string>
<key>CFBundleSupportedPlatforms</key><array><string>SUPPORTED_PLATFORM</string></array>
<key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
<key>UILaunchScreen</key><dict/>
<key>CFBundleIcons</key><dict><key>CFBundlePrimaryIcon</key><dict>
<key>CFBundleIconFiles</key><array><string>AppIcon60x60</string></array></dict></dict>
<key>CFBundleIcons~ipad</key><dict><key>CFBundlePrimaryIcon</key><dict>
<key>CFBundleIconFiles</key><array><string>AppIcon60x60</string><string>AppIcon76x76</string><string>AppIcon83.5x83.5</string></array></dict></dict>
<key>UIApplicationSceneManifest</key><dict>
<key>UIApplicationSupportsMultipleScenes</key><false/>
</dict>
<key>UIRequiresFullScreen</key><true/>
<key>UIBackgroundModes</key><array><string>audio</string></array>
<key>UISupportedInterfaceOrientations</key><array>
<string>UIInterfaceOrientationLandscapeLeft</string>
<string>UIInterfaceOrientationLandscapeRight</string>
</array>
<key>UISupportedInterfaceOrientations~ipad</key><array>
<string>UIInterfaceOrientationLandscapeLeft</string>
<string>UIInterfaceOrientationLandscapeRight</string>
</array>
<key>NSMicrophoneUsageDescription</key><string>Talk to other players through your PlayStation console while you stream.</string>
<key>NSPhotoLibraryAddUsageDescription</key><string>Add the screenshots and video clips you take in PS5 cloud games to your Photos library.</string>
<key>NSLocalNetworkUsageDescription</key><string>Find your PlayStation consoles on local networks and configured discovery subnets.</string>
<key>LSApplicationCategoryType</key><string>public.app-category.games</string>
<key>LSSupportsGameMode</key><true/>
<key>UTExportedTypeDeclarations</key><array><dict>
<key>UTTypeIdentifier</key><string>io.github.chiaki-ng.kakusan</string>
<key>UTTypeDescription</key><string>Kakusan invitation or reply</string>
<key>UTTypeConformsTo</key><array><string>public.data</string><string>public.content</string></array>
<key>UTTypeTagSpecification</key><dict><key>public.filename-extension</key><array><string>kakusan</string></array></dict>
</dict></array>
<key>CFBundleDocumentTypes</key><array><dict>
<key>CFBundleTypeName</key><string>Kakusan invitation or reply</string>
<key>CFBundleTypeRole</key><string>Viewer</string>
<key>LSHandlerRank</key><string>Owner</string>
<key>LSItemContentTypes</key><array><string>io.github.chiaki-ng.kakusan</string></array>
</dict></array>
<key>CFBundleURLTypes</key><array><dict>
<key>CFBundleURLName</key><string>BUNDLE_ID.stream</string>
<key>CFBundleTypeRole</key><string>Viewer</string>
<key>CFBundleURLSchemes</key><array><string>chiaki-ng</string></array>
</dict></array>
</dict></plist>
PLIST
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $bundle_id" \
    -c "Set :CFBundleSupportedPlatforms:0 $supported_platform" \
    -c "Set :CFBundleURLTypes:0:CFBundleURLName $bundle_id.stream" "$app_dir/Info.plist"
localizations=("$app_dir"/ChiakiNG_ChiakiFeatures.bundle/*.lproj(N:t:r))
/usr/libexec/PlistBuddy -c "Add :CFBundleDevelopmentRegion string en" -c "Add :CFBundleLocalizations array" \
    "$app_dir/Info.plist"
for localization in "${localizations[@]}"; do
    /usr/libexec/PlistBuddy -c "Add :CFBundleLocalizations: string $localization" "$app_dir/Info.plist"
done
if [[ "${CHIAKI_KAKUSAN:-0}" == 0 ]]; then
    /usr/libexec/PlistBuddy -c "Delete :UTExportedTypeDeclarations" -c "Delete :CFBundleDocumentTypes" \
        "$app_dir/Info.plist"
fi
"$project_dir/Tools/Packaging/bundle-dylibs.sh" \
    "$app_dir" \
    "$app_dir/ChiakiNG" \
    "$app_dir/Frameworks/libChiakiRegistration.dylib" \
    "$app_dir/Frameworks/libChiakiInput.dylib"
python3 "$project_dir/Tools/Packaging/verify-ios.py" "$platform" "$app_dir/ChiakiNG" "$app_dir"/Frameworks/*.dylib
if [[ "$platform" == ios-simulator ]]; then
    codesign --force --sign - "$app_dir"/Frameworks/*.dylib
    codesign --force --sign - "$app_dir"
    if [[ "${CHIAKI_LAUNCH_APP:-1}" == 1 ]]; then
        xcrun simctl install "$device" "$app_dir"
        xcrun simctl launch "$device" "$bundle_id"
    else
        printf 'Built %s\n' "$app_dir"
    fi
    exit 0
fi
identity="${IOS_SIGN_IDENTITY:-Apple Development}"
team="${IOS_TEAM:-}"
if [[ -z "$team" ]]; then
    team="$(security find-certificate -c "$identity" -p | openssl x509 -noout -subject \
        | sed -n 's/.*OU=\([A-Z0-9]*\).*/\1/p')"
fi
if [[ -z "$team" ]]; then
    echo "No development team found for signing identity: $identity. Set IOS_TEAM." >&2
    exit 1
fi
provisioning_dir="$project_dir/.build/ios/provisioning"
python3 "$project_dir/Tools/Packaging/provision-ios.py" "$team" "$bundle_id" "$provisioning_dir" \
    ${IOS_MULTICAST:+--multicast}
cp "$provisioning_dir/embedded.mobileprovision" "$app_dir/embedded.mobileprovision"
codesign --force --sign "$identity" "$app_dir"/Frameworks/*.dylib
codesign --force --sign "$identity" --entitlements "$provisioning_dir/signed.entitlements" "$app_dir"
codesign --verify --deep --strict "$app_dir"
if [[ "${IOS_IPA:-0}" == 1 ]]; then
    ipa_root="$project_dir/.build/ios/ipa"
    ipa_path="$project_dir/.build/ios/chiaki-ng.ipa"
    rm -rf "$ipa_root" "$ipa_path"
    mkdir -p "$ipa_root/Payload"
    ditto "$app_dir" "$ipa_root/Payload/chiaki-ng.app"
    ditto -c -k --keepParent "$ipa_root/Payload" "$ipa_path"
    rm -rf "$ipa_root"
    printf 'Built %s\n' "$ipa_path"
    exit 0
fi
if [[ "${CHIAKI_LAUNCH_APP:-1}" != 1 ]]; then
    printf 'Built %s\n' "$app_dir"
    exit 0
fi
if [[ -z "$device" ]]; then
    echo 'Set IOS_DEVICE to a device name or identifier from: xcrun devicectl list devices' >&2
    exit 1
fi
xcrun devicectl device install app --device "$device" "$app_dir"
xcrun devicectl device process launch --device "$device" "$bundle_id"
