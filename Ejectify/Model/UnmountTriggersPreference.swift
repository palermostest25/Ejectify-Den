//
//  UnmountTriggersPreference.swift
//  Ejectify
//
//  Created by Codex on 04/09/2026.
//

import Foundation

/// Persists the set of events that trigger automatic unmounting, including migration from the single-trigger format.
enum UnmountTriggersPreference {

    /// Stable defaults key holding the selected triggers as raw values.
    static let key = "preference.unmountTriggers"

    /// Defaults key written by Ejectify 1 and Ejectify 2.1 and earlier, kept for restore compatibility.
    static let legacyKey = "preference.unmountWhen"

    /// Reads the selected triggers, migrating the legacy single-trigger value the first time it is needed.
    static func value(in userDefaults: UserDefaults) -> Set<UnmountTrigger> {
        guard let persistedRawValues = userDefaults.array(forKey: key) as? [String] else {
            return migrateLegacyValue(in: userDefaults)
        }

        let triggers = Set(persistedRawValues.compactMap(UnmountTrigger.init(rawValue:)))
        guard !triggers.isEmpty else {
            Log.preferences.warning("Persisted unmount triggers contained no known values; using default trigger")
            return [UnmountTrigger.legacyDefault]
        }

        return triggers
    }

    /// Persists a non-empty trigger selection and reports whether it was accepted.
    @discardableResult
    static func set(_ triggers: Set<UnmountTrigger>, in userDefaults: UserDefaults) -> Bool {
        guard !triggers.isEmpty else {
            Log.preferences.warning("Rejected empty unmount trigger selection; keeping the previous selection")
            return false
        }

        userDefaults.set(sortedRawValues(of: triggers), forKey: key)
        return true
    }

    /// Returns raw values in a stable order for persistence and logging.
    static func sortedRawValues(of triggers: Set<UnmountTrigger>) -> [String] {
        UnmountTrigger.allCases
            .filter(triggers.contains)
            .map(\.rawValue)
    }

    /// Converts the legacy single-trigger value into the new set, writing it once so later reads skip this path.
    private static func migrateLegacyValue(in userDefaults: UserDefaults) -> Set<UnmountTrigger> {
        let legacyRawValue = userDefaults.string(forKey: legacyKey)
        // The legacy initializer intentionally maps unknown and missing values onto the default trigger.
        let migratedTriggers: Set<UnmountTrigger> = [UnmountTrigger(persistedRawValue: legacyRawValue)]
        userDefaults.set(sortedRawValues(of: migratedTriggers), forKey: key)
        Log.preferences.log("Migrated unmount trigger preference; triggers=\(sortedRawValues(of: migratedTriggers).joined(separator: ","))")
        return migratedTriggers
    }
}
