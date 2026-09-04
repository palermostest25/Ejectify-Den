//
//  KnownPowerAdaptersPreference.swift
//  Ejectify
//
//  Created by Codex on 04/09/2026.
//

import Foundation

/// Remembers which power adapters Ejectify has seen so the menu can offer them while they are unplugged.
enum KnownPowerAdaptersPreference {

    /// Stable defaults key holding the seen adapters as JSON.
    static let key = "preference.knownPowerAdapters"

    /// Maximum adapters kept, so the menu stays short and old adapters age out.
    static let limit = 8

    /// Reads the seen adapters, most recently connected first.
    static func value(in userDefaults: UserDefaults) -> [PowerAdapterIdentity] {
        guard let data = userDefaults.data(forKey: key) else {
            return []
        }

        do {
            return try JSONDecoder().decode([PowerAdapterIdentity].self, from: data)
        } catch {
            Log.preferences.warning("Could not read known power adapters; treating the list as empty")
            return []
        }
    }

    /// Persists the seen adapters.
    static func set(_ adapters: [PowerAdapterIdentity], in userDefaults: UserDefaults) {
        guard !adapters.isEmpty else {
            userDefaults.removeObject(forKey: key)
            return
        }

        do {
            userDefaults.set(try JSONEncoder().encode(adapters), forKey: key)
        } catch {
            Log.preferences.error("Could not save known power adapters; count=\(adapters.count)")
        }
    }

    /// Returns the list with `adapter` moved to the front, replacing any earlier reading of the same adapter.
    static func list(_ adapters: [PowerAdapterIdentity], recording adapter: PowerAdapterIdentity) -> [PowerAdapterIdentity] {
        // A later reading usually carries more complete details, so it replaces the earlier one.
        var updatedAdapters = adapters.filter { !$0.matches(adapter) }
        updatedAdapters.insert(adapter, at: 0)
        return Array(updatedAdapters.prefix(limit))
    }

    /// Records one adapter and reports whether it was not already the most recent entry.
    @discardableResult
    static func record(_ adapter: PowerAdapterIdentity, in userDefaults: UserDefaults) -> Bool {
        let existingAdapters = value(in: userDefaults)
        let updatedAdapters = list(existingAdapters, recording: adapter)

        guard updatedAdapters != existingAdapters else {
            return false
        }

        set(updatedAdapters, in: userDefaults)
        return true
    }
}
