import ChiakiModels
import Testing
@testable import ChiakiFeatures

@Test func appVersionShowsTheVersionWithoutABuildNumber() {
    #expect(AppVersion.display(version: "2.0.0", tag: nil) == "v2.0.0")
    #expect(AppVersion.display(version: "2.0.0", tag: "") == "v2.0.0")
}

@Test func appVersionAppendsTheBuildTag() {
    #expect(AppVersion.display(version: "2.0.0", tag: "grill") == "v2.0.0-grill")
}

@Test func appVersionFallsBackWhenTheBundleHasNoVersion() {
    #expect(AppVersion.display(version: nil, tag: nil) == "v2.0.0")
    #expect(AppVersion.display(version: "", tag: "grill") == "v2.0.0-grill")
}

@Test func appVersionShowsTheCommitItWasBuiltFrom() {
    #expect(AppVersion.display(version: "2.0.0", tag: nil, commit: "3b36e55a") == "v2.0.0 (3b36e55a)")
    #expect(AppVersion.display(version: "2.0.0", tag: "grill", commit: "3b36e55a-modified")
        == "v2.0.0-grill (3b36e55a-modified)")
    #expect(AppVersion.display(version: "2.0.0", tag: nil, commit: "") == "v2.0.0")
}
