//
//  GuardedApplicationTests.swift
//  EjectifyTests
//
//  Created by Codex on 08/09/2026.
//

import Foundation
import Testing

struct GuardedApplicationTests {

    /// Builds a running application snapshot without repeating the defaults in every test.
    private func makeRunningApplication(bundleIdentifier: String? = nil, name: String = "App", isUserFacing: Bool = true, bundleURL: URL? = nil) -> RunningApplication {
        RunningApplication(bundleIdentifier: bundleIdentifier, name: name, isUserFacing: isUserFacing, bundleURL: bundleURL)
    }

    @Test func bundleIdentifierDecidesTheMatch() {
        let guarded = GuardedApplication(bundleIdentifier: "com.pioneerdj.rekordbox", name: "rekordbox")

        // The user renamed the app on disk, but the bundle identifier still identifies it.
        #expect(guarded.matches(makeRunningApplication(bundleIdentifier: "com.pioneerdj.rekordbox", name: "rekordbox 7")))
        #expect(guarded.matches(makeRunningApplication(bundleIdentifier: "com.apple.logic10", name: "rekordbox")) == false)
    }

    @Test func bundleIdentifierComparisonIgnoresCase() {
        let guarded = GuardedApplication(bundleIdentifier: "com.PioneerDJ.rekordbox", name: "rekordbox")

        #expect(guarded.matches(makeRunningApplication(bundleIdentifier: "com.pioneerdj.REKORDBOX", name: "rekordbox")))
    }

    @Test func nameOnlyMatchingAppliesOnlyWhenNeitherSideHasABundleIdentifier() {
        let namedOnly = GuardedApplication(bundleIdentifier: nil, name: "Some Tool")

        #expect(namedOnly.matches(makeRunningApplication(bundleIdentifier: nil, name: "some tool")))
        // A running app that does have an identifier is a different, identifiable app.
        #expect(namedOnly.matches(makeRunningApplication(bundleIdentifier: "com.example.tool", name: "Some Tool")) == false)

        let identified = GuardedApplication(bundleIdentifier: "com.example.tool", name: "Some Tool")
        #expect(identified.matches(makeRunningApplication(bundleIdentifier: nil, name: "Some Tool")) == false)
    }

    @Test func nameMatchingIgnoresCaseAccentsAndSurroundingSpace() {
        let guarded = GuardedApplication(bundleIdentifier: nil, name: " Ableton Live ")

        #expect(guarded.matches(makeRunningApplication(bundleIdentifier: nil, name: "ableton live")))
        #expect(guarded.matches(makeRunningApplication(bundleIdentifier: nil, name: "Ábleton Live")))
        #expect(guarded.matches(makeRunningApplication(bundleIdentifier: nil, name: "Ableton Push")) == false)
    }

    @Test func blankBundleIdentifierIsTreatedAsAbsent() {
        let guarded = GuardedApplication(bundleIdentifier: "   ", name: "Tool")

        #expect(guarded.bundleIdentifier == nil)
        #expect(guarded.matches(makeRunningApplication(bundleIdentifier: nil, name: "Tool")))
    }

    @Test func identityFoldsCaseSoOneAppNeverAppearsTwice() {
        #expect(GuardedApplication(bundleIdentifier: "com.example.Tool", name: "Tool").id
            == GuardedApplication(bundleIdentifier: "com.EXAMPLE.tool", name: "Renamed").id)
        #expect(GuardedApplication(bundleIdentifier: nil, name: "Tool").id
            == GuardedApplication(bundleIdentifier: nil, name: "tool").id)
        // An identified app and a name-only app are never the same entry.
        #expect(GuardedApplication(bundleIdentifier: "com.example.tool", name: "Tool").id
            != GuardedApplication(bundleIdentifier: nil, name: "Tool").id)
    }

    @Test func isRunningScansEveryRunningApplication() {
        let guarded = GuardedApplication(bundleIdentifier: "com.pioneerdj.rekordbox", name: "rekordbox")
        let running = [
            makeRunningApplication(bundleIdentifier: "com.apple.finder", name: "Finder"),
            makeRunningApplication(bundleIdentifier: "com.pioneerdj.rekordbox", name: "rekordbox")
        ]

        #expect(guarded.isRunning(among: running))
        #expect(guarded.isRunning(among: []) == false)
    }

    @Test func codableRoundTripPreservesEveryField() throws {
        let guarded = GuardedApplication(bundleIdentifier: "com.pioneerdj.rekordbox", name: "rekordbox")

        let encoded = try JSONEncoder().encode(guarded)
        #expect(try JSONDecoder().decode(GuardedApplication.self, from: encoded) == guarded)
    }
}
