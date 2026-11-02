@testable import ChiakiFeatures
import ChiakiModels
import ComposableArchitecture
import DesignSystem
import PlatformUI
import SwiftUI
import Testing

@MainActor @Test(arguments: [ColorScheme.light, .dark])
func welcomeAndProfilesRenderForVisualChecks(appearance: ColorScheme) throws {
    guard let directory = ProcessInfo.processInfo.environment["CHIAKI_RENDER_CHECK_DIR"] else {
        return
    }
    let appearanceName = appearance == .dark
        ? "dark"
        : "light"
    try renderProfiles(directory: directory, appearance: appearance, appearanceName: appearanceName)
    try renderWelcome(directory: directory, appearance: appearance, appearanceName: appearanceName)
}

@MainActor private func renderWelcome(
    directory: String,
    appearance: ColorScheme,
    appearanceName: String
) throws {
    let page = ImageRenderer(
        content: RootView(
            store: Store(initialState: RootFeature.State(route: .welcome)) {
                RootFeature()
            }
        )
        .environment(\.colorScheme, appearance)
        .frame(width: 760, height: 600)
    )
    page.scale = 2
    let snapshot = try #require(page.cgImage)
    let data = try #require(
        NSBitmapImageRep(cgImage: snapshot).representation(using: .png, properties: [:])
    )
    try data.write(
        to: URL(fileURLWithPath: directory).appendingPathComponent(
            "welcome-\(appearanceName).png"
        )
    )
}

@MainActor private func renderProfiles(
    directory: String,
    appearance: ColorScheme,
    appearanceName: String
) throws {
    let profile = UUID()
    @Shared(.accounts) var accounts
    @Shared(.selectedAccount) var selected
    $accounts.withLock {
        $0 = [.init(id: profile, name: "Player", kind: .npsso, accountID: nil)]
    }
    $selected.withLock {
        $0 = profile
    }
    for size in [CGSize(width: 1920, height: 1080), CGSize(width: 480, height: 800)] {
        let profiles = ImageRenderer(
            content: ZStack {
                AmbientBackground(previewTime: 0, quiet: true)
                LibraryView(
                    store: Store(initialState: LibraryFeature.State()) {
                        LibraryFeature()
                    }
                )
            }
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, appearance)
        )
        let shot = try #require(profiles.cgImage)
        let data = try #require(
            NSBitmapImageRep(cgImage: shot).representation(using: .png, properties: [:])
        )
        try data.write(
            to: URL(fileURLWithPath: directory).appendingPathComponent(
                "profiles-\(Int(size.width))-\(appearanceName).png"
            )
        )
    }
}
