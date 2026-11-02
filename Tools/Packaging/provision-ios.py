from pathlib import Path
import datetime
import plistlib
import shutil
import subprocess
import sys

PROJECT = Path(__file__).resolve().parents[2]
ROOT = PROJECT / ".build/ios-provisioning"
PBXPROJ = """// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {};
	objectVersion = 56;
	objects = {
		A10000000000000000000001 = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = main.swift; sourceTree = "<group>"; };
		A10000000000000000000002 = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Stub.app; sourceTree = BUILT_PRODUCTS_DIR; };
		A10000000000000000000003 = {isa = PBXBuildFile; fileRef = A10000000000000000000001; };
		A10000000000000000000004 = {isa = PBXGroup; children = (A10000000000000000000001, A10000000000000000000002); sourceTree = "<group>"; };
		A10000000000000000000005 = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (A10000000000000000000003); runOnlyForDeploymentPostprocessing = 0; };
		A10000000000000000000006 = {isa = PBXNativeTarget; buildConfigurationList = A10000000000000000000009; buildPhases = (A10000000000000000000005); buildRules = (); dependencies = (); name = Stub; productName = Stub; productReference = A10000000000000000000002; productType = "com.apple.product-type.application"; };
		A10000000000000000000007 = {isa = PBXProject; attributes = {LastUpgradeCheck = 2700; }; buildConfigurationList = A1000000000000000000000B; compatibilityVersion = "Xcode 14.0"; mainGroup = A10000000000000000000004; productRefGroup = A10000000000000000000004; projectDirPath = ""; projectRoot = ""; targets = (A10000000000000000000006); };
		A10000000000000000000008 = {isa = XCBuildConfiguration; buildSettings = {CODE_SIGN_ENTITLEMENTS = Stub.entitlements; CODE_SIGN_STYLE = Automatic; DEVELOPMENT_TEAM = __TEAM__; GENERATE_INFOPLIST_FILE = YES; INFOPLIST_KEY_UILaunchScreen_Generation = YES; IPHONEOS_DEPLOYMENT_TARGET = 26.0; PRODUCT_BUNDLE_IDENTIFIER = "__BUNDLE__"; PRODUCT_NAME = Stub; SDKROOT = iphoneos; SWIFT_VERSION = 5.0; TARGETED_DEVICE_FAMILY = "1,2"; }; name = Debug; };
		A10000000000000000000009 = {isa = XCConfigurationList; buildConfigurations = (A10000000000000000000008); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug; };
		A1000000000000000000000A = {isa = XCBuildConfiguration; buildSettings = {}; name = Debug; };
		A1000000000000000000000B = {isa = XCConfigurationList; buildConfigurations = (A1000000000000000000000A); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug; };
	};
	rootObject = A10000000000000000000007;
}
"""

arguments = [argument for argument in sys.argv[1:] if argument != "--multicast"]
if len(arguments) != 3:
    raise SystemExit("usage: provision-ios.py TEAM_ID BUNDLE_ID OUTPUT_DIRECTORY [--multicast]")
team, bundle, output = arguments[0], arguments[1], Path(arguments[2])
requested = {"com.apple.developer.networking.multicast": True} if "--multicast" in sys.argv else {}
PROFILES = [Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles",
            Path.home() / "Library/MobileDevice/Provisioning Profiles"]


def installed_profile():
    found = []
    for path in (path for folder in PROFILES if folder.is_dir() for path in folder.glob("*.mobileprovision")):
        decoded = subprocess.run(["security", "cms", "-D", "-i", str(path)], capture_output=True)
        if decoded.returncode:
            continue
        profile = plistlib.loads(decoded.stdout)
        identifier = profile.get("Entitlements", {}).get("application-identifier", "")
        if team not in profile.get("TeamIdentifier", []) or identifier.partition(".")[2] not in (bundle, "*"):
            continue
        if profile["ExpirationDate"] < datetime.datetime.now(profile["ExpirationDate"].tzinfo):
            continue
        found.append((identifier.endswith(f".{bundle}"), profile["CreationDate"], path, profile))
    if not found:
        return None
    return max(found, key=lambda entry: entry[:2])[2:]


def adopt_installed_profile():
    match = installed_profile()
    if match is None:
        return False
    path, profile = match
    entitlements = dict(profile["Entitlements"])
    prefix = entitlements["application-identifier"].partition(".")[0]
    entitlements["application-identifier"] = f"{prefix}.{bundle}"
    output.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(path, output / "embedded.mobileprovision")
    with (output / "signed.entitlements").open("wb") as stream:
        plistlib.dump(entitlements, stream)
    print(f"Provisioned {bundle} for team {team} from the installed profile {profile['Name']}")
    return True


shutil.rmtree(ROOT / "build", ignore_errors=True)
(ROOT / "Stub.xcodeproj").mkdir(parents=True, exist_ok=True)
(ROOT / "Stub.xcodeproj/project.pbxproj").write_text(PBXPROJ.replace("__TEAM__", team).replace("__BUNDLE__", bundle))
(ROOT / "main.swift").write_text("import UIKit\n\nUIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, nil)\n")
with (ROOT / "Stub.entitlements").open("wb") as entitlements:
    plistlib.dump(requested, entitlements)
log = ROOT / "xcodebuild.log"
with log.open("w") as stream:
    result = subprocess.run(
        ["xcodebuild", "-project", str(ROOT / "Stub.xcodeproj"), "-target", "Stub", "-configuration", "Debug",
         "-sdk", "iphoneos", "-allowProvisioningUpdates", "-allowProvisioningDeviceRegistration",
         f"SYMROOT={ROOT / 'build'}", "build"],
        cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT)
if result.returncode:
    if adopt_installed_profile():
        raise SystemExit(0)
    failures = [line for line in log.read_text(errors="replace").splitlines() if "error:" in line]
    raise SystemExit("\n".join(failures[-8:] + [
        f"Xcode could not provision {bundle} for team {team}; see {log}",
        f"Open {ROOT / 'Stub.xcodeproj'} in Xcode, run Stub on the device once, then run this again"]))
app = ROOT / "build/Debug-iphoneos/Stub.app"
output.mkdir(parents=True, exist_ok=True)
shutil.copyfile(app / "embedded.mobileprovision", output / "embedded.mobileprovision")
signed = subprocess.check_output(["codesign", "-d", "--entitlements", "-", "--xml", str(app)], stderr=subprocess.DEVNULL)
(output / "signed.entitlements").write_bytes(signed)
print(f"Provisioned {bundle} for team {team}")
