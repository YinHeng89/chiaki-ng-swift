// swift-tools-version: 6.2
import PackageDescription
import Foundation

let coreBuildDirectories = [
    "macos": ".build/native-core",
    "ios": ".build/native-core-ios",
    "ios-simulator": ".build/native-core-ios-simulator"
]

let corePlatform = ProcessInfo.processInfo.environment["CHIAKI_PLATFORM"] ?? "macos"

guard let coreBuildDirectory = coreBuildDirectories[corePlatform] else {
    fatalError("CHIAKI_PLATFORM must be macos, ios or ios-simulator")
}

let kakusanSwitch = ProcessInfo.processInfo.environment["CHIAKI_KAKUSAN"] ?? "0"

guard let kakusanIncluded = ["1": true, "0": false][kakusanSwitch] else {
    fatalError("CHIAKI_KAKUSAN must be 1 or 0")
}

let kakusan: [SwiftSetting] = kakusanIncluded
    ? [.define("CHIAKI_KAKUSAN")]
    : []

let ps5CloudLaunchSwitch = ProcessInfo.processInfo.environment["CHIAKI_PS5_CLOUD_LAUNCH"] ?? "0"

guard let ps5CloudLaunchIncluded = ["1": true, "0": false][ps5CloudLaunchSwitch] else {
    fatalError("CHIAKI_PS5_CLOUD_LAUNCH must be 1 or 0")
}

let ps5CloudLaunch: [SwiftSetting] = ps5CloudLaunchIncluded
    ? [.define("CHIAKI_PS5_CLOUD_LAUNCH")]
    : []

let coreBuildPath = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent(coreBuildDirectory).path

let coreIncludePath = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("lib/chiaki-ng-core/include").path

let bridgeIncludePath = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("lib/bridge/include").path

let videoIncludes = ["-I", coreIncludePath, "-I", bridgeIncludePath]

let upscalerFrameworks: [LinkerSetting] = corePlatform == "ios-simulator"
    ? []
    : [.linkedFramework("MetalFX")]

let coreLinkage: [LinkerSetting] = [
    .unsafeFlags([
        "-L", coreBuildPath,
        "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
        "-Xlinker", "-rpath", "-Xlinker", "@executable_path/Frameworks",
        "-Xlinker", "-rpath", "-Xlinker", coreBuildPath
    ])
]

let generatedSwiftHeaderPath = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent(".build/out/Intermediates.noindex/GeneratedModuleMaps").path

let cxxVisibleSwift: [SwiftSetting] = [
    .unsafeFlags(["-Xfrontend", "-clang-header-expose-decls=all-public"])
]

let coreInterop: [SwiftSetting] = [
    .interoperabilityMode(.Cxx),
    .unsafeFlags([
        "-Xcc", "-I" + coreIncludePath, "-Xcc", "-I" + bridgeIncludePath
    ])
]

let composableArchitecture = Target.Dependency.product(
    name: "ComposableArchitecture",
    package: "swift-composable-architecture"
)

let dependencies = Target.Dependency.product(name: "Dependencies", package: "swift-dependencies")

let package = Package(
    name: "ChiakiNG",
    defaultLocalization: "en",
    platforms: [.macOS("26.0"), .iOS("26.0")],
    products: [.executable(name: "ChiakiNG", targets: ["ChiakiNG"])],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", exact: "1.26.2"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", exact: "1.17.1"),
        .package(url: "https://github.com/groue/GRDB.swift", exact: "7.11.1")
    ],
    targets: [
        .executableTarget(
            name: "ChiakiNG",
            dependencies: [
                "ChiakiAssets", "PlatformUI", "Video", "CInput",
                "ChiakiCore", "ChiakiBridge", "ChiakiModels", "ChiakiDiagnostics", "ChiakiPersistence",
                "ChiakiCoreBridge",
                "ChiakiClients", "ChiakiClientsLive", "ChiakiFeatures", "DesignSystem", "MenuFocus",
                composableArchitecture, dependencies
            ],
            swiftSettings: coreInterop + kakusan,
            linkerSettings: [.linkedFramework("GameController")]
        ),
        .target(name: "PlatformUI"),
        .target(
            name: "DesignSystem",
            dependencies: ["ChiakiModels", "PlatformUI", "ChiakiAssets"],
            resources: [.process("Resources")]
        ),
        .target(
            name: "MenuFocus",
            dependencies: ["ChiakiModels", "DesignSystem", "PlatformUI"],
            resources: [.process("Resources")]
        ),
        .target(
            name: "ChiakiTestSupport",
            dependencies: ["ChiakiModels", "ChiakiClients", "DesignSystem", "MenuFocus", "PlatformUI"],
            path: "Tests/ChiakiTestSupport"
        ),
        .target(
            name: "ChiakiAssets",
            path: "Assets",
            exclude: [
                "UPSTREAM-COPYING",
                "Images/Branding/chiaki.svg",
                "ThirdParty/FSRCNNX/FSRCNNX_x2_16-0-4-1.glsl"
            ],
            resources: [
                .process("Images"),
                .process("Video"),
                .process("ThirdParty/FSRCNNX"),
                .copy("Licenses")
            ]
        ),
        .target(
            name: "Video",
            dependencies: ["ChiakiBridge"],
            cxxSettings: [.unsafeFlags(videoIncludes)],
            linkerSettings: [
                .linkedFramework("Foundation"), .linkedFramework("VideoToolbox"),
                .linkedFramework("CoreMedia"), .linkedFramework("CoreVideo"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalPerformanceShaders"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("AppKit", .when(platforms: [.macOS])),
                .linkedFramework("UIKit", .when(platforms: [.iOS])),
                .linkedFramework("AVFoundation"),
                .linkedFramework("GameController"), .linkedFramework("CoreHaptics"),
                .linkedFramework("CoreAudio", .when(platforms: [.macOS]))
            ] + upscalerFrameworks
        ),
        .target(name: "ChiakiModels", resources: [.process("Resources")], swiftSettings: kakusan + ps5CloudLaunch),
        .target(name: "ChiakiDiagnostics", dependencies: ["ChiakiModels", dependencies]),
        .target(
            name: "ChiakiPersistence",
            dependencies: ["ChiakiModels", .product(name: "GRDB", package: "GRDB.swift")],
            resources: [.copy("Resources/Migrations")],
            swiftSettings: cxxVisibleSwift
        ),
        .target(
            name: "ChiakiStoreAdapters",
            dependencies: ["ChiakiPersistence"],
            cxxSettings: [
                .headerSearchPath("../../lib/chiaki-ng-core/include"),
                .headerSearchPath("../../lib/bridge"),
                .unsafeFlags(["-I", generatedSwiftHeaderPath])
            ],
            linkerSettings: coreLinkage + [.linkedLibrary("ChiakiRegistration")]
        ),
        .target(
            name: "ChiakiCoreBridge",
            dependencies: [
                "ChiakiModels", "ChiakiPersistence", "ChiakiStoreAdapters", "ChiakiBridge"
            ],
            swiftSettings: coreInterop + kakusan
        ),
        .target(
            name: "ChiakiClients",
            dependencies: ["ChiakiModels", composableArchitecture, dependencies]
        ),
        .target(
            name: "ChiakiClientsLive",
            dependencies: [
                "ChiakiClients",
                "ChiakiModels",
                "ChiakiDiagnostics",
                "ChiakiPersistence",
                "ChiakiCoreBridge",
                "ChiakiBridge",
                "PlatformUI",
                "Video",
                composableArchitecture,
                dependencies
            ],
            swiftSettings: coreInterop + kakusan
        ),
        .target(
            name: "ChiakiFeatures",
            dependencies: [
                "ChiakiModels", "ChiakiClients", "ChiakiDiagnostics", "DesignSystem", "MenuFocus",
                "PlatformUI",
                "ChiakiAssets", composableArchitecture, dependencies
            ],
            resources: [.process("Resources")]
        ),
        .systemLibrary(name: "ChiakiCore", path: "Sources/CBridge/ChiakiCore"),
        .systemLibrary(name: "ChiakiBridge", path: "Sources/CBridge/ChiakiBridge"),
        .systemLibrary(name: "CInput", path: "Sources/CBridge/CInput"),
        .testTarget(
            name: "ChiakiNGTests",
            dependencies: [
                "ChiakiNG", "ChiakiAssets", "PlatformUI", "Video", "ChiakiCore", "ChiakiModels",
                "ChiakiDiagnostics", "ChiakiBridge", "ChiakiPersistence", "ChiakiCoreBridge", "ChiakiClients",
                "ChiakiClientsLive", "ChiakiFeatures",
                "DesignSystem", "MenuFocus", "ChiakiTestSupport", composableArchitecture
            ],
            swiftSettings: coreInterop + kakusan
        ),
        .testTarget(name: "ChiakiModelsTests", dependencies: ["ChiakiModels"]),
        .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem", "PlatformUI"]),
        .testTarget(
            name: "MenuFocusTests",
            dependencies: ["MenuFocus", "DesignSystem", "PlatformUI", "ChiakiTestSupport"]
        ),
        .testTarget(
            name: "ChiakiDiagnosticsTests",
            dependencies: ["ChiakiDiagnostics", "ChiakiModels", dependencies]
        ),
        .testTarget(
            name: "ChiakiPersistenceTests",
            dependencies: ["ChiakiPersistence", "ChiakiModels", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(
            name: "ChiakiCoreBridgeTests",
            dependencies: [
                "ChiakiCoreBridge", "ChiakiStoreAdapters", "ChiakiPersistence", "ChiakiModels",
                "ChiakiBridge", "ChiakiTestSupport"
            ],
            swiftSettings: coreInterop + kakusan
        ),
        .testTarget(
            name: "ChiakiClientsLiveTests",
            dependencies: [
                "ChiakiClientsLive", "ChiakiBridge", "ChiakiClients", "ChiakiModels", "ChiakiPersistence",
                "ChiakiTestSupport",
                composableArchitecture
            ],
            swiftSettings: coreInterop
        ),
        .testTarget(
            name: "ChiakiFeaturesTests",
            dependencies: [
                "ChiakiFeatures",
                "ChiakiClients",
                "ChiakiDiagnostics",
                "ChiakiModels",
                "DesignSystem",
                "MenuFocus",
                "PlatformUI",
                "ChiakiTestSupport",
                composableArchitecture
            ],
            swiftSettings: kakusan
        ),
        .testTarget(name: "ChiakiAssetsTests", dependencies: ["ChiakiAssets"])
    ],
    cxxLanguageStandard: .gnucxx2b
)
