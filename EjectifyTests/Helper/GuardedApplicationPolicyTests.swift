//
//  GuardedApplicationPolicyTests.swift
//  EjectifyTests
//
//  Created by Codex on 08/09/2026.
//

import Foundation
import Testing

struct GuardedApplicationPolicyTests {

    private let rekordbox = GuardedApplication(bundleIdentifier: "com.pioneerdj.rekordbox", name: "rekordbox")
    private let logic = GuardedApplication(bundleIdentifier: "com.apple.logic10", name: "Logic Pro")

    /// Builds a running application snapshot without repeating the defaults in every test.
    private func makeRunningApplication(_ bundleIdentifier: String?, _ name: String, isUserFacing: Bool = true) -> RunningApplication {
        RunningApplication(bundleIdentifier: bundleIdentifier, name: name, isUserFacing: isUserFacing)
    }

    @Test func nothingIsBlockedWhenNoApplicationIsGuarded() {
        let running = [makeRunningApplication("com.pioneerdj.rekordbox", "rekordbox")]

        #expect(GuardedApplicationPolicy.blockingApplications(guardedApplications: [], runningApplications: running).isEmpty)
    }

    @Test func nothingIsBlockedWhenNoGuardedApplicationRuns() {
        let running = [makeRunningApplication("com.apple.finder", "Finder")]

        #expect(GuardedApplicationPolicy.blockingApplications(guardedApplications: [rekordbox, logic], runningApplications: running).isEmpty)
    }

    @Test func aRunningGuardedApplicationBlocks() {
        let running = [
            makeRunningApplication("com.apple.finder", "Finder"),
            makeRunningApplication("com.pioneerdj.rekordbox", "rekordbox")
        ]

        #expect(GuardedApplicationPolicy.blockingApplications(guardedApplications: [rekordbox, logic], runningApplications: running) == [rekordbox])
    }

    @Test func blockingApplicationsKeepTheOrderTheUserAddedThem() {
        let running = [
            makeRunningApplication("com.apple.logic10", "Logic Pro"),
            makeRunningApplication("com.pioneerdj.rekordbox", "rekordbox")
        ]

        #expect(GuardedApplicationPolicy.blockingApplications(guardedApplications: [rekordbox, logic], runningApplications: running) == [rekordbox, logic])
    }

    @Test func aBackgroundGuardedApplicationStillBlocks() {
        // The picker only offers apps with a Dock icon, but one already guarded may run as an agent.
        let running = [makeRunningApplication("com.pioneerdj.rekordbox", "rekordbox", isUserFacing: false)]

        #expect(GuardedApplicationPolicy.blockingApplications(guardedApplications: [rekordbox], runningApplications: running) == [rekordbox])
    }

    @Test func noRunningApplicationsBlocksNothing() {
        #expect(GuardedApplicationPolicy.blockingApplications(guardedApplications: [rekordbox], runningApplications: []).isEmpty)
    }

    @Test func descriptionListsEveryBlockingName() {
        #expect(GuardedApplicationPolicy.description(of: [rekordbox, logic]) == "rekordbox, Logic Pro")
        #expect(GuardedApplicationPolicy.description(of: []).isEmpty)
    }

    @Test func logDescriptionCarriesIdentifiersRatherThanUserFacingNames() {
        #expect(GuardedApplicationPolicy.logDescription(of: [rekordbox, logic]) == "com.pioneerdj.rekordbox,com.apple.logic10")
        #expect(GuardedApplicationPolicy.logDescription(of: []) == "none")
        // An app without an identifier is reduced to a count, because its name may be user-authored.
        let unnamed = GuardedApplication(bundleIdentifier: nil, name: "Private Tool")
        #expect(GuardedApplicationPolicy.logDescription(of: [unnamed]) == "count=1")
    }

    @Test func selectableApplicationsMergeGuardedAndRunningAppsWithoutDuplicates() {
        let running = [
            makeRunningApplication("com.pioneerdj.rekordbox", "rekordbox"),
            makeRunningApplication("com.apple.finder", "Finder")
        ]

        let selectable = GuardedApplicationPolicy.selectableApplications(guardedApplications: [rekordbox], runningApplications: running)

        // rekordbox is both guarded and running, and must appear exactly once.
        #expect(selectable.map(\.name) == ["Finder", "rekordbox"])
    }

    @Test func selectableApplicationsKeepAGuardedAppThatHasQuit() {
        // Without this there would be no row left to untick.
        let selectable = GuardedApplicationPolicy.selectableApplications(guardedApplications: [logic], runningApplications: [])

        #expect(selectable == [logic])
    }

    @Test func selectableApplicationsOfferOnlyUserFacingRunningApps() {
        let running = [
            makeRunningApplication("com.apple.dock", "Dock", isUserFacing: false),
            makeRunningApplication("com.apple.finder", "Finder")
        ]

        #expect(GuardedApplicationPolicy.selectableApplications(guardedApplications: [], runningApplications: running).map(\.name) == ["Finder"])
    }

    @Test func selectableApplicationsExcludeTheExcludedIdentifier() {
        let running = [
            makeRunningApplication("com.palermostest25.Ejectify", "Ejectify"),
            makeRunningApplication("com.apple.finder", "Finder")
        ]

        let selectable = GuardedApplicationPolicy.selectableApplications(
            guardedApplications: [],
            runningApplications: running,
            excludingBundleIdentifier: "com.palermostest25.Ejectify"
        )

        #expect(selectable.map(\.name) == ["Finder"])
    }

    @Test func selectableApplicationsAreSortedByName() {
        let running = [
            makeRunningApplication("com.example.zulu", "Zulu"),
            makeRunningApplication("com.example.alpha", "alpha"),
            makeRunningApplication("com.example.mike", "Mike")
        ]

        #expect(GuardedApplicationPolicy.selectableApplications(guardedApplications: [], runningApplications: running).map(\.name)
            == ["alpha", "Mike", "Zulu"])
    }
}
