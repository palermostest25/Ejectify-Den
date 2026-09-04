//
//  RememberedDocksPreference.swift
//  Ejectify
//
//  Created by Codex on 04/09/2026.
//

import Foundation

/// Persists the power adapters the user marked as docks, stored as JSON so adapter fields can grow over time.
enum RememberedDocksPreference {

    /// Stable defaults key holding the remembered docks as JSON.
    static let key = "preference.rememberedDocks"

    /// Reads the remembered docks, returning an empty list when nothing is stored or the stored value is unreadable.
    static func value(in userDefaults: UserDefaults) -> [PowerAdapterIdentity] {
        guard let data = userDefaults.data(forKey: key) else {
            return []
        }

        do {
            return try JSONDecoder().decode([PowerAdapterIdentity].self, from: data)
        } catch {
            Log.preferences.warning("Could not read remembered docks; treating the list as empty")
            return []
        }
    }

    /// Persists the remembered docks, removing the stored value when the list is empty.
    static func set(_ rememberedDocks: [PowerAdapterIdentity], in userDefaults: UserDefaults) {
        guard !rememberedDocks.isEmpty else {
            userDefaults.removeObject(forKey: key)
            return
        }

        do {
            userDefaults.set(try JSONEncoder().encode(rememberedDocks), forKey: key)
        } catch {
            Log.preferences.error("Could not save remembered docks; count=\(rememberedDocks.count)")
        }
    }
}
