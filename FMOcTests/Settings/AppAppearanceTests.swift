import SwiftUI
import Testing
@testable import FMOc

@MainActor
struct AppAppearanceTests {
    @Test func appearanceCasesHaveExpectedSchemes() {
        #expect(AppAppearance.system.colorScheme == nil)
        #expect(AppAppearance.light.colorScheme == .light)
        #expect(AppAppearance.dark.colorScheme == .dark)
    }

    @Test func unknownStoredValueCanFallBackToSystem() {
        let restored = AppAppearance(rawValue: "future-value") ?? .system

        #expect(restored == .system)
    }

    @Test func appMetadataBuildsProductVersionDescription() {
        let metadata = AppMetadata()

        #expect(!metadata.name.isEmpty)
        #expect(!metadata.version.isEmpty)
        #expect(!metadata.build.isEmpty)
        #expect(metadata.versionDescription == "\(metadata.version) (\(metadata.build))")
    }
}
