//
//  UnmountTriggersPreferenceTests.swift
//  EjectifyTests
//
//  Created by Codex on 04/09/2026.
//

import Foundation
import Testing

struct UnmountTriggersPreferenceTests {

    @Test func legacySingleTriggerMigratesToTheNewKey() {
        let (userDefaults, suiteName) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        userDefaults.set("screenIsLocked", forKey: UnmountTriggersPreference.legacyKey)

        #expect(UnmountTriggersPreference.value(in: userDefaults) == [.screenIsLocked])
        #expect(userDefaults.array(forKey: UnmountTriggersPreference.key) as? [String] == ["screenIsLocked"])
    }

    @Test func migrationKeepsTheLegacyKeyForRestores() {
        let (userDefaults, suiteName) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        userDefaults.set("screensaverStarted", forKey: UnmountTriggersPreference.legacyKey)
        _ = UnmountTriggersPreference.value(in: userDefaults)

        #expect(userDefaults.string(forKey: UnmountTriggersPreference.legacyKey) == "screensaverStarted")
    }

    @Test func unknownLegacyValueMigratesToTheDefaultTrigger() {
        let (userDefaults, suiteName) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        userDefaults.set("somethingElse", forKey: UnmountTriggersPreference.legacyKey)

        #expect(UnmountTriggersPreference.value(in: userDefaults) == [.systemStartsSleeping])
    }

    @Test func missingLegacyValueMigratesToTheDefaultTrigger() {
        let (userDefaults, suiteName) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        #expect(UnmountTriggersPreference.value(in: userDefaults) == [.systemStartsSleeping])
    }

    @Test func multipleTriggersPersistAndAreReadBack() {
        let (userDefaults, suiteName) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        #expect(UnmountTriggersPreference.set([.dockDisconnected, .systemStartsSleeping], in: userDefaults))
        #expect(UnmountTriggersPreference.value(in: UserDefaults(suiteName: suiteName)!) == [.systemStartsSleeping, .dockDisconnected])
    }

    @Test func emptySelectionIsRejectedAndKeepsThePreviousSelection() {
        let (userDefaults, suiteName) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        UnmountTriggersPreference.set([.externalDisplayDisconnected], in: userDefaults)

        #expect(UnmountTriggersPreference.set([], in: userDefaults) == false)
        #expect(UnmountTriggersPreference.value(in: userDefaults) == [.externalDisplayDisconnected])
    }

    @Test func unknownPersistedValuesFallBackToTheDefaultTrigger() {
        let (userDefaults, suiteName) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        userDefaults.set(["somethingElse"], forKey: UnmountTriggersPreference.key)

        #expect(UnmountTriggersPreference.value(in: userDefaults) == [.systemStartsSleeping])
    }

    @Test func unknownPersistedValuesAreDroppedFromAKnownSelection() {
        let (userDefaults, suiteName) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        userDefaults.set(["dockDisconnected", "somethingElse"], forKey: UnmountTriggersPreference.key)

        #expect(UnmountTriggersPreference.value(in: userDefaults) == [.dockDisconnected])
    }

    @Test func rawValuesAreSortedInDeclarationOrder() {
        let rawValues = UnmountTriggersPreference.sortedRawValues(of: [.externalDisplayDisconnected, .systemStartsSleeping, .screenIsLocked])

        #expect(rawValues == ["systemStartsSleeping", "screenIsLocked", "externalDisplayDisconnected"])
    }

    /// Creates a unique defaults suite so tests never modify the app's actual preferences.
    private func makeIsolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "UnmountTriggersPreferenceTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return (userDefaults, suiteName)
    }
}
