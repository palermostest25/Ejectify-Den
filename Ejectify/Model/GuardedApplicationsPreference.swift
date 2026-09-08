//
//  GuardedApplicationsPreference.swift
//  Ejectify
//
//  Created by Codex on 08/09/2026.
//

import Foundation

/// Persists the applications that block automatic disk operations, stored as JSON so fields can grow.
enum GuardedApplicationsPreference {

    /// Stable defaults key holding the guarded applications as JSON.
    static let key = "preference.guardedApplications"

    /// Reads the guarded applications, returning an empty list when nothing is stored or it is unreadable.
    static func value(in userDefaults: UserDefaults) -> [GuardedApplication] {
        guard let data = userDefaults.data(forKey: key) else {
            return []
        }

        do {
            return try JSONDecoder().decode([GuardedApplication].self, from: data)
        } catch {
            Log.preferences.warning("Could not read guarded applications; treating the list as empty")
            return []
        }
    }

    /// Persists the guarded applications, removing the stored value when the list is empty.
    static func set(_ guardedApplications: [GuardedApplication], in userDefaults: UserDefaults) {
        guard !guardedApplications.isEmpty else {
            userDefaults.removeObject(forKey: key)
            return
        }

        do {
            userDefaults.set(try JSONEncoder().encode(guardedApplications), forKey: key)
        } catch {
            Log.preferences.error("Could not save guarded applications; count=\(guardedApplications.count)")
        }
    }

    /// Returns the list with `application` added, keeping the existing entry when it is already guarded.
    static func list(_ guardedApplications: [GuardedApplication], adding application: GuardedApplication) -> [GuardedApplication] {
        guard !guardedApplications.contains(where: { $0.id == application.id }) else {
            return guardedApplications
        }

        return guardedApplications + [application]
    }

    /// Returns the list with every entry describing `application` removed.
    static func list(_ guardedApplications: [GuardedApplication], removing application: GuardedApplication) -> [GuardedApplication] {
        guardedApplications.filter { $0.id != application.id }
    }
}
