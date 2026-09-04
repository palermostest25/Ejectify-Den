//
//  GlobalShortcutPreference.swift
//  Ejectify
//
//  Created by Codex on 04/09/2026.
//

import Foundation

/// Persists the global keyboard shortcut bound to each action.
enum GlobalShortcutPreference {

    /// Defaults key holding one action's shortcut.
    static func key(for action: GlobalShortcut.Action) -> String {
        "preference.shortcut.\(action.rawValue)"
    }

    /// Reads an action's shortcut, falling back to its default when unset or unreadable.
    static func value(for action: GlobalShortcut.Action, in userDefaults: UserDefaults) -> GlobalShortcut {
        guard let data = userDefaults.data(forKey: key(for: action)) else {
            return action.defaultShortcut
        }

        do {
            return try JSONDecoder().decode(GlobalShortcut.self, from: data)
        } catch {
            Log.preferences.warning("Could not read shortcut; action=\(action.rawValue); using the default")
            return action.defaultShortcut
        }
    }

    /// Persists an action's shortcut, or restores its default when `shortcut` is `nil`.
    static func set(_ shortcut: GlobalShortcut?, for action: GlobalShortcut.Action, in userDefaults: UserDefaults) {
        guard let shortcut else {
            userDefaults.removeObject(forKey: key(for: action))
            return
        }

        do {
            userDefaults.set(try JSONEncoder().encode(shortcut), forKey: key(for: action))
        } catch {
            Log.preferences.error("Could not save shortcut; action=\(action.rawValue)")
        }
    }

    /// Returns the action already using `shortcut`, so a duplicate binding can be refused.
    static func conflictingAction(
        with shortcut: GlobalShortcut,
        excluding action: GlobalShortcut.Action,
        in userDefaults: UserDefaults
    ) -> GlobalShortcut.Action? {
        GlobalShortcut.Action.allCases.first { otherAction in
            otherAction != action && value(for: otherAction, in: userDefaults) == shortcut
        }
    }
}
