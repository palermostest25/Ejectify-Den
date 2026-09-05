//
//  PowerAdapterIdentityTests.swift
//  EjectifyTests
//
//  Created by Codex on 04/09/2026.
//

import Foundation
import Testing

struct PowerAdapterIdentityTests {

    @Test func serialMatchWinsOverMismatchingFields() {
        let dock = PowerAdapterIdentity(adapterID: 1, familyCode: 10, manufacturer: "CalDigit", model: "TS4", serial: "ABC123")
        let sameDockReportedDifferently = PowerAdapterIdentity(adapterID: 2, familyCode: 20, manufacturer: "Other", model: "Other", serial: "ABC123")

        #expect(dock.matches(sameDockReportedDifferently))
    }

    @Test func differingSerialsNeverMatch() {
        let dock = PowerAdapterIdentity(adapterID: 1, familyCode: 10, manufacturer: "CalDigit", model: "TS4", serial: "ABC123")
        let otherDock = PowerAdapterIdentity(adapterID: 1, familyCode: 10, manufacturer: "CalDigit", model: "TS4", serial: "XYZ789")

        #expect(dock.matches(otherDock) == false)
    }

    @Test func twoEqualFieldsMatchWhenOtherFieldsAreMissing() {
        let dock = PowerAdapterIdentity(adapterID: 4, familyCode: 12, manufacturer: "CalDigit", model: "TS4")
        let partialReading = PowerAdapterIdentity(adapterID: 4, familyCode: 12)

        #expect(dock.matches(partialReading))
        #expect(partialReading.matches(dock))
    }

    @Test func singleEqualFieldIsNotEnoughToMatch() {
        let dock = PowerAdapterIdentity(adapterID: 4, familyCode: 12, manufacturer: "CalDigit", model: "TS4")
        let partialReading = PowerAdapterIdentity(adapterID: 4)

        #expect(dock.matches(partialReading) == false)
    }

    @Test func conflictingFieldPreventsMatch() {
        let dock = PowerAdapterIdentity(adapterID: 4, familyCode: 12, manufacturer: "CalDigit", model: "TS4")
        let charger = PowerAdapterIdentity(adapterID: 4, familyCode: 12, manufacturer: "Apple Inc.", model: "TS4")

        #expect(dock.matches(charger) == false)
    }

    @Test func manufacturerAndModelMatchIgnoresCaseAndWhitespace() {
        let dock = PowerAdapterIdentity(manufacturer: "CalDigit", model: "TS4")
        let sameDock = PowerAdapterIdentity(manufacturer: " caldigit ", model: "ts4")

        #expect(dock.matches(sameDock))
    }

    @Test func equalWattageAloneNeverMatches() {
        let dock = PowerAdapterIdentity(watts: 96, serial: "ABC123")
        let charger = PowerAdapterIdentity(watts: 96)

        #expect(dock.matches(charger) == false)
        #expect(charger.matches(dock) == false)
    }

    @Test func appleChargersAreRecognizedAsAHint() {
        #expect(PowerAdapterIdentity(manufacturer: "Apple Inc.").isLikelyAppleCharger)
        #expect(PowerAdapterIdentity(name: "96W MagSafe Power Adapter").isLikelyAppleCharger)
        #expect(PowerAdapterIdentity(manufacturer: "CalDigit", name: "TS4").isLikelyAppleCharger == false)
    }

    @Test func logDescriptionExcludesSerialAndName() {
        let dock = PowerAdapterIdentity(
            adapterID: 4,
            manufacturer: "CalDigit",
            name: "Thunderbolt Station 4",
            watts: 96,
            serial: "SECRET-SERIAL"
        )

        let logDescription = dock.logDescription

        #expect(logDescription.contains("SECRET-SERIAL") == false)
        #expect(logDescription.contains("Thunderbolt Station 4") == false)
        #expect(logDescription.contains("CalDigit"))
        #expect(logDescription.contains("96"))
        #expect(logDescription.contains("4"))
    }

    @Test func logDescriptionMarksMissingFieldsAsUnknown() {
        #expect(PowerAdapterIdentity().logDescription == "manufacturer=unknown; watts=unknown; adapterID=unknown")
    }

    @Test func displayNameCombinesNameAndWattage() {
        let dock = PowerAdapterIdentity(manufacturer: "CalDigit", name: "CalDigit TS4", watts: 96)

        #expect(dock.displayName == "CalDigit TS4 (96 W)")
    }

    @Test func adapterDetailsInitializerReadsIOKitFields() {
        let adapter = PowerAdapterIdentity(adapterDetails: [
            "AdapterID": 4,
            "FamilyCode": 12,
            "Manufacturer": "CalDigit",
            "Name": "CalDigit TS4",
            "Model": "TS4",
            "Watts": 96,
            "SerialString": "ABC123"
        ])

        #expect(adapter?.adapterID == 4)
        #expect(adapter?.familyCode == 12)
        #expect(adapter?.manufacturer == "CalDigit")
        #expect(adapter?.model == "TS4")
        #expect(adapter?.watts == 96)
        #expect(adapter?.serial == "ABC123")
        #expect(adapter?.displayName == "CalDigit TS4 (96 W)")
    }

    @Test func adapterDetailsInitializerRejectsEmptyDictionaries() {
        #expect(PowerAdapterIdentity(adapterDetails: [:]) == nil)
    }

    @Test func adapterDetailsInitializerAcceptsNumericSerials() {
        let adapter = PowerAdapterIdentity(adapterDetails: ["SerialNumber": 1234])

        #expect(adapter?.serial == "1234")
    }

    @Test func codableRoundTripPreservesEveryField() throws {
        let dock = PowerAdapterIdentity(
            adapterID: 4,
            familyCode: 12,
            manufacturer: "CalDigit",
            name: "CalDigit TS4",
            model: "TS4",
            watts: 96,
            serial: "ABC123"
        )

        let decodedDock = try JSONDecoder().decode(PowerAdapterIdentity.self, from: JSONEncoder().encode(dock))

        #expect(decodedDock == dock)
    }

    @Test func adaptersMacOSCannotIdentifyDoNotMatchEachOther() {
        // Both a dock and a charger report a zero adapter ID when macOS cannot identify them.
        let dock = PowerAdapterIdentity(adapterID: 0, familyCode: 1, watts: 90)
        let charger = PowerAdapterIdentity(adapterID: 0, familyCode: 1, watts: 65)

        #expect(dock.matches(charger) == false)
        #expect(dock.isIdentifiable == false)
    }

    @Test func differentWattageDisprovesAMatch() {
        let dock = PowerAdapterIdentity(adapterID: 4, familyCode: 12, watts: 90)
        let charger = PowerAdapterIdentity(adapterID: 4, familyCode: 12, watts: 65)

        #expect(dock.matches(charger) == false)
        // The same adapter reporting no wattage on one reading still matches.
        #expect(dock.matches(PowerAdapterIdentity(adapterID: 4, familyCode: 12)))
    }

    @Test func identifiableRequiresASerialOrTwoComparableFields() {
        #expect(PowerAdapterIdentity(serial: "SERIAL-1").isIdentifiable)
        #expect(PowerAdapterIdentity(adapterID: 4, familyCode: 12).isIdentifiable)
        #expect(PowerAdapterIdentity(manufacturer: "CalDigit", model: "TS4").isIdentifiable)
        #expect(PowerAdapterIdentity(adapterID: 4).isIdentifiable == false)
        #expect(PowerAdapterIdentity(watts: 96).isIdentifiable == false)
        #expect(PowerAdapterIdentity().isIdentifiable == false)
        // Blank strings carry no information, so they do not count as a comparable field.
        #expect(PowerAdapterIdentity(adapterID: 4, manufacturer: "  ").isIdentifiable == false)
    }

    @Test func remembersDocksByMatchingRatherThanEquality() {
        let rememberedDock = PowerAdapterIdentity(adapterID: 4, familyCode: 12, manufacturer: "CalDigit", model: "TS4")
        let partialReading = PowerAdapterIdentity(adapterID: 4, familyCode: 12)

        #expect(partialReading.isRemembered(in: [rememberedDock]))
        #expect(PowerAdapterIdentity(adapterID: 9, familyCode: 99).isRemembered(in: [rememberedDock]) == false)
    }

    @Test func wattageOnlyMatchingIsOffByDefault() {
        // The reading a Mac gives for an adapter it cannot describe: a wattage and nothing usable.
        let dock = PowerAdapterIdentity(adapterID: 0, familyCode: 1, watts: 100)
        let sameDock = PowerAdapterIdentity(adapterID: 0, familyCode: 1, watts: 100)

        #expect(dock.hasOnlyWattage)
        #expect(dock.matches(sameDock) == false)
        #expect(dock.matches(sameDock, allowingWattageOnly: true))
    }

    @Test func wattageOnlyMatchingStillRespectsDifferingWattage() {
        let dock = PowerAdapterIdentity(adapterID: 0, familyCode: 1, watts: 100)
        let charger = PowerAdapterIdentity(adapterID: 0, familyCode: 1, watts: 65)

        #expect(dock.matches(charger, allowingWattageOnly: true) == false)
    }

    @Test func wattageOnlyMatchingNeverAppliesToADescribedAdapter() {
        let describedDock = PowerAdapterIdentity(adapterID: 4, familyCode: 12, watts: 100)
        let undescribedCharger = PowerAdapterIdentity(watts: 100)

        #expect(describedDock.hasOnlyWattage == false)
        #expect(describedDock.matches(undescribedCharger, allowingWattageOnly: true) == false)
        #expect(undescribedCharger.matches(describedDock, allowingWattageOnly: true) == false)
    }

    @Test func anAdapterWithoutAWattageIsNeverMatchedByWattage() {
        let dock = PowerAdapterIdentity(adapterID: 0)
        let charger = PowerAdapterIdentity(adapterID: 0)

        #expect(dock.hasOnlyWattage == false)
        #expect(dock.matches(charger, allowingWattageOnly: true) == false)
    }

    @Test func remembersAWattageOnlyDockUnlessAskedNotTo() {
        let rememberedDock = PowerAdapterIdentity(adapterID: 0, familyCode: 1, watts: 100)
        let sameDock = PowerAdapterIdentity(adapterID: 0, familyCode: 1, watts: 100)
        let charger = PowerAdapterIdentity(adapterID: 0, familyCode: 1, watts: 65)

        #expect(sameDock.isRemembered(in: [rememberedDock]))
        #expect(charger.isRemembered(in: [rememberedDock]) == false)
        #expect(sameDock.isRemembered(in: [rememberedDock], allowingWattageOnly: false) == false)
    }
}
