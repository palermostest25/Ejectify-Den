//
//  KnownPowerAdaptersPreferenceTests.swift
//  EjectifyTests
//
//  Created by Codex on 04/09/2026.
//

import Foundation
import Testing

struct KnownPowerAdaptersPreferenceTests {

    /// Creates an adapter that carries enough detail to be matched again.
    private func makeAdapter(id: Int, serial: String? = nil) -> PowerAdapterIdentity {
        PowerAdapterIdentity(adapterID: id, familyCode: id * 10, manufacturer: "Maker\(id)", model: "Model\(id)", watts: 96, serial: serial)
    }

    @Test func recordingPutsTheNewestAdapterFirst() {
        let first = makeAdapter(id: 1)
        let second = makeAdapter(id: 2)

        let adapters = KnownPowerAdaptersPreference.list([first], recording: second)

        #expect(adapters == [second, first])
    }

    @Test func recordingTheSameAdapterDoesNotDuplicateIt() {
        let adapter = makeAdapter(id: 1, serial: "SERIAL-1")
        let laterReading = PowerAdapterIdentity(adapterID: 1, familyCode: 10, manufacturer: "Maker1", model: "Model1", watts: 100, serial: "SERIAL-1")

        let adapters = KnownPowerAdaptersPreference.list([adapter], recording: laterReading)

        #expect(adapters.count == 1)
        // The newer, more complete reading replaces the older one.
        #expect(adapters.first?.watts == 100)
    }

    @Test func anAdapterMacOSCannotDescribeCollapsesIntoOneEntry() {
        // Without wattage matching every reconnection of this adapter would add another identical row.
        let firstReading = PowerAdapterIdentity(adapterID: 0, familyCode: 1, watts: 100)
        let secondReading = PowerAdapterIdentity(adapterID: 0, familyCode: 1, watts: 100)
        let charger = PowerAdapterIdentity(adapterID: 0, familyCode: 1, watts: 65)

        var adapters = KnownPowerAdaptersPreference.list([firstReading], recording: secondReading)
        #expect(adapters.count == 1)

        adapters = KnownPowerAdaptersPreference.list(adapters, recording: charger)
        #expect(adapters == [charger, secondReading])
    }

    @Test func recordingMovesAKnownAdapterBackToTheFront() {
        let first = makeAdapter(id: 1)
        let second = makeAdapter(id: 2)

        let adapters = KnownPowerAdaptersPreference.list([second, first], recording: first)

        #expect(adapters == [first, second])
    }

    @Test func theListIsCappedAtTheLimit() {
        let existing = (1...KnownPowerAdaptersPreference.limit).map { makeAdapter(id: $0) }

        let adapters = KnownPowerAdaptersPreference.list(existing, recording: makeAdapter(id: 99))

        #expect(adapters.count == KnownPowerAdaptersPreference.limit)
        #expect(adapters.first?.adapterID == 99)
        // The oldest entry is the one that ages out.
        #expect(adapters.contains { $0.adapterID == KnownPowerAdaptersPreference.limit } == false)
    }

    @Test func recordingPersistsAndReportsWhetherItChangedAnything() {
        let (userDefaults, suiteName) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let adapter = makeAdapter(id: 1, serial: "SERIAL-1")

        #expect(KnownPowerAdaptersPreference.record(adapter, in: userDefaults))
        #expect(KnownPowerAdaptersPreference.value(in: userDefaults) == [adapter])
        #expect(KnownPowerAdaptersPreference.record(adapter, in: userDefaults) == false)
    }

    @Test func unreadableValueIsTreatedAsNoAdapters() {
        let (userDefaults, suiteName) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        userDefaults.set(Data("not json".utf8), forKey: KnownPowerAdaptersPreference.key)

        #expect(KnownPowerAdaptersPreference.value(in: userDefaults).isEmpty)
    }

    /// Creates a unique defaults suite so tests never modify the app's actual preferences.
    private func makeIsolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "KnownPowerAdaptersPreferenceTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return (userDefaults, suiteName)
    }
}
