//
//  GuardedApplicationsPreferenceTests.swift
//  EjectifyTests
//
//  Created by Codex on 08/09/2026.
//

import Foundation
import Testing

struct GuardedApplicationsPreferenceTests {

    private let rekordbox = GuardedApplication(bundleIdentifier: "com.pioneerdj.rekordbox", name: "rekordbox")
    private let logic = GuardedApplication(bundleIdentifier: "com.apple.logic10", name: "Logic Pro")

    @Test func addingKeepsTheOrderTheUserChose() {
        let guardedApplications = GuardedApplicationsPreference.list([rekordbox], adding: logic)

        #expect(guardedApplications == [rekordbox, logic])
    }

    @Test func addingTheSameApplicationTwiceChangesNothing() {
        // The same app read again reports the same identifier under a newer name.
        let renamed = GuardedApplication(bundleIdentifier: "com.pioneerdj.rekordbox", name: "rekordbox 7")

        let guardedApplications = GuardedApplicationsPreference.list([rekordbox], adding: renamed)

        #expect(guardedApplications == [rekordbox])
    }

    @Test func removingDropsOnlyTheMatchingEntry() {
        let guardedApplications = GuardedApplicationsPreference.list([rekordbox, logic], removing: rekordbox)

        #expect(guardedApplications == [logic])
    }

    @Test func removingAnApplicationThatIsNotGuardedChangesNothing() {
        #expect(GuardedApplicationsPreference.list([rekordbox], removing: logic) == [rekordbox])
    }

    @Test func storedApplicationsSurviveARoundTrip() {
        let (userDefaults, suiteName) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        GuardedApplicationsPreference.set([rekordbox, logic], in: userDefaults)

        #expect(GuardedApplicationsPreference.value(in: userDefaults) == [rekordbox, logic])
    }

    @Test func anEmptyListClearsTheStoredValue() {
        let (userDefaults, suiteName) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        GuardedApplicationsPreference.set([rekordbox], in: userDefaults)
        GuardedApplicationsPreference.set([], in: userDefaults)

        #expect(userDefaults.data(forKey: GuardedApplicationsPreference.key) == nil)
        #expect(GuardedApplicationsPreference.value(in: userDefaults).isEmpty)
    }

    @Test func unreadableValueIsTreatedAsNoGuardedApplications() {
        let (userDefaults, suiteName) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        userDefaults.set(Data("not json".utf8), forKey: GuardedApplicationsPreference.key)

        #expect(GuardedApplicationsPreference.value(in: userDefaults).isEmpty)
    }

    /// Creates a unique defaults suite so tests never modify the app's actual preferences.
    private func makeIsolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "GuardedApplicationsPreferenceTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return (userDefaults, suiteName)
    }
}
