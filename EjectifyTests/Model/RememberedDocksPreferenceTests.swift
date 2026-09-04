//
//  RememberedDocksPreferenceTests.swift
//  EjectifyTests
//
//  Created by Codex on 04/09/2026.
//

import Foundation
import Testing

struct RememberedDocksPreferenceTests {

    @Test func missingValueReturnsNoDocks() {
        let (userDefaults, suiteName) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        #expect(RememberedDocksPreference.value(in: userDefaults).isEmpty)
    }

    @Test func docksPersistAcrossReads() {
        let (userDefaults, suiteName) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let dock = PowerAdapterIdentity(adapterID: 4, familyCode: 12, manufacturer: "CalDigit", name: "CalDigit TS4", model: "TS4", watts: 96, serial: "DOCK-1")
        RememberedDocksPreference.set([dock], in: userDefaults)

        #expect(RememberedDocksPreference.value(in: UserDefaults(suiteName: suiteName)!) == [dock])
    }

    @Test func emptyListRemovesTheStoredValue() {
        let (userDefaults, suiteName) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        RememberedDocksPreference.set([PowerAdapterIdentity(adapterID: 4, familyCode: 12)], in: userDefaults)
        RememberedDocksPreference.set([], in: userDefaults)

        #expect(userDefaults.data(forKey: RememberedDocksPreference.key) == nil)
        #expect(RememberedDocksPreference.value(in: userDefaults).isEmpty)
    }

    @Test func unreadableValueIsTreatedAsNoDocks() {
        let (userDefaults, suiteName) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        userDefaults.set(Data("not json".utf8), forKey: RememberedDocksPreference.key)

        #expect(RememberedDocksPreference.value(in: userDefaults).isEmpty)
    }

    /// Creates a unique defaults suite so tests never modify the app's actual preferences.
    private func makeIsolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "RememberedDocksPreferenceTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return (userDefaults, suiteName)
    }
}
