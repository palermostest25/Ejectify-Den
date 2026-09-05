//
//  PowerAdapterIdentity.swift
//  Ejectify
//
//  Created by Codex on 04/09/2026.
//

import Foundation

/// Identifies an external power adapter well enough to tell a remembered dock apart from a plain charger.
struct PowerAdapterIdentity: Codable, Hashable, Sendable {

    /// Adapter identifier reported by IOKit.
    var adapterID: Int?

    /// Adapter family code reported by IOKit.
    var familyCode: Int?

    /// Adapter manufacturer reported by IOKit.
    var manufacturer: String?

    /// Adapter marketing name reported by IOKit.
    var name: String?

    /// Adapter model reported by IOKit.
    var model: String?

    /// Adapter wattage reported by IOKit.
    var watts: Int?

    /// Adapter serial used for matching only, never logged or included in diagnostics.
    var serial: String?

    /// User-facing adapter description shown in the menu.
    var displayName: String

    /// Creates an identity from explicit values, deriving a display name when none is supplied.
    init(
        adapterID: Int? = nil,
        familyCode: Int? = nil,
        manufacturer: String? = nil,
        name: String? = nil,
        model: String? = nil,
        watts: Int? = nil,
        serial: String? = nil,
        displayName: String? = nil
    ) {
        self.adapterID = adapterID
        self.familyCode = familyCode
        self.manufacturer = manufacturer
        self.name = name
        self.model = model
        self.watts = watts
        self.serial = serial
        self.displayName = displayName ?? Self.makeDisplayName(manufacturer: manufacturer, name: name, model: model, watts: watts)
    }

    /// Creates an identity from an `IOPSCopyExternalPowerAdapterDetails()` dictionary.
    init?(adapterDetails: [String: Any]) {
        guard !adapterDetails.isEmpty else {
            return nil
        }

        self.init(
            adapterID: Self.intValue(in: adapterDetails, forKey: "AdapterID"),
            familyCode: Self.intValue(in: adapterDetails, forKey: "FamilyCode"),
            manufacturer: Self.stringValue(in: adapterDetails, forKey: "Manufacturer"),
            name: Self.stringValue(in: adapterDetails, forKey: "Name"),
            model: Self.stringValue(in: adapterDetails, forKey: "Model"),
            watts: Self.intValue(in: adapterDetails, forKey: "Watts"),
            // Apple silicon reports "SerialString"; Intel Macs report a numeric "SerialNumber".
            serial: Self.stringValue(in: adapterDetails, forKey: "SerialString") ?? Self.stringValue(in: adapterDetails, forKey: "SerialNumber")
        )
    }

    /// Whether both identities describe the same physical adapter.
    func matches(_ other: PowerAdapterIdentity) -> Bool {
        if let serial = Self.normalized(serial), let otherSerial = Self.normalized(other.serial) {
            return serial == otherSerial
        }

        // Wattage can never prove two adapters are the same, but a known difference disproves it:
        // a 90 W dock and a 65 W charger are not one adapter, whatever else they report.
        if let watts, let otherWatts = other.watts, watts != otherWatts {
            return false
        }

        var comparedFieldCount = 0

        guard Self.compare(Self.meaningfulIdentifier(adapterID), Self.meaningfulIdentifier(other.adapterID), matchCount: &comparedFieldCount),
              Self.compare(Self.meaningfulIdentifier(familyCode), Self.meaningfulIdentifier(other.familyCode), matchCount: &comparedFieldCount),
              Self.compare(Self.normalized(manufacturer), Self.normalized(other.manufacturer), matchCount: &comparedFieldCount),
              Self.compare(Self.normalized(model), Self.normalized(other.model), matchCount: &comparedFieldCount) else {
            return false
        }

        // A single shared field is too weak to identify an adapter, so nil is only treated as a wildcard beyond that.
        return comparedFieldCount >= 2
    }

    /// Whether this reading carries enough detail for `matches(_:)` to recognize the adapter again.
    var isIdentifiable: Bool {
        if Self.normalized(serial) != nil {
            return true
        }

        // `matches(_:)` needs at least two comparable fields, so a thinner reading can never match.
        let comparableFieldCount = [
            Self.meaningfulIdentifier(adapterID) != nil,
            Self.meaningfulIdentifier(familyCode) != nil,
            Self.normalized(manufacturer) != nil,
            Self.normalized(model) != nil
        ].filter { $0 }.count
        return comparableFieldCount >= 2
    }

    /// Whether the adapter looks like an Apple charger, used only as a user-facing hint.
    var isLikelyAppleCharger: Bool {
        if let manufacturer, manufacturer.localizedCaseInsensitiveContains("Apple") {
            return true
        }

        guard let name else {
            return false
        }

        return name.localizedCaseInsensitiveContains("MagSafe")
    }

    /// Privacy-safe adapter correlation fields for logs and diagnostics, deliberately excluding the serial and marketing name.
    var logDescription: String {
        let manufacturerDescription = Self.trimmed(manufacturer) ?? Self.unknownLogValue
        let wattsDescription = watts.map(String.init) ?? Self.unknownLogValue
        let adapterIDDescription = adapterID.map(String.init) ?? Self.unknownLogValue
        return "manufacturer=\(manufacturerDescription); watts=\(wattsDescription); adapterID=\(adapterIDDescription)"
    }

    /// Placeholder used in logs when an adapter field is unavailable.
    private static let unknownLogValue = "unknown"

    /// Returns whether a remembered list already contains this adapter.
    func isRemembered(in rememberedDocks: [PowerAdapterIdentity]) -> Bool {
        rememberedDocks.contains { $0.matches(self) }
    }

    /// Compares one optional field, counting it only when both sides provide a value.
    private static func compare<Value: Equatable>(_ value: Value?, _ otherValue: Value?, matchCount: inout Int) -> Bool {
        guard let value, let otherValue else {
            return true
        }

        guard value == otherValue else {
            return false
        }

        matchCount += 1
        return true
    }

    /// Returns an identifier only when it distinguishes anything. Macs report zero for adapters they
    /// cannot identify, so treating zero as a value makes every unidentified adapter look alike.
    private static func meaningfulIdentifier(_ value: Int?) -> Int? {
        guard let value, value != 0 else {
            return nil
        }

        return value
    }

    /// Returns a trimmed, case-folded string, or `nil` when the value is missing or blank.
    private static func normalized(_ value: String?) -> String? {
        trimmed(value)?.lowercased()
    }

    /// Returns a trimmed string, or `nil` when the value is missing or blank.
    private static func trimmed(_ value: String?) -> String? {
        guard let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmedValue.isEmpty else {
            return nil
        }

        return trimmedValue
    }

    /// Reads a string field, accepting numeric values reported by older power management interfaces.
    private static func stringValue(in adapterDetails: [String: Any], forKey key: String) -> String? {
        if let stringValue = adapterDetails[key] as? String {
            return trimmed(stringValue)
        }

        guard let numberValue = adapterDetails[key] as? NSNumber else {
            return nil
        }

        return numberValue.stringValue
    }

    /// Reads an integer field from a power adapter details dictionary.
    private static func intValue(in adapterDetails: [String: Any], forKey key: String) -> Int? {
        if let numberValue = adapterDetails[key] as? NSNumber {
            return numberValue.intValue
        }

        return (adapterDetails[key] as? String).flatMap(Int.init)
    }

    /// Builds the user-facing adapter description shown in the menu.
    private static func makeDisplayName(manufacturer: String?, name: String?, model: String?, watts: Int?) -> String {
        let baseName = [name, model, manufacturer]
            .compactMap(trimmed)
            .first ?? String(localized: "Power adapter")
        guard let watts else {
            return baseName
        }

        return "\(baseName) (\(watts) W)"
    }
}
