//
//  GuardedApplication.swift
//  Ejectify
//
//  Created by Codex on 08/09/2026.
//

import Foundation

/// One application the user asked Ejectify to respect: while it runs, its volumes are left mounted.
struct GuardedApplication: Codable, Hashable, Sendable {

    /// Bundle identifier of the application, absent only for an app macOS reports without one.
    let bundleIdentifier: String?

    /// Name shown in the menu, and the fallback identity for an app that has no bundle identifier.
    let name: String

    init(bundleIdentifier: String?, name: String) {
        self.bundleIdentifier = Self.normalized(bundleIdentifier)
        self.name = name
    }

    /// Stable key used to de-duplicate the list and to identify menu rows.
    var id: String {
        guard let bundleIdentifier = Self.normalized(bundleIdentifier) else {
            return "name:\(Self.foldedName(name))"
        }

        return "bundle:\(bundleIdentifier.lowercased())"
    }

    /// Whether a running application is this guarded application.
    func matches(_ runningApplication: RunningApplication) -> Bool {
        // A bundle identifier is the only field that survives renames, updates and localization,
        // so whenever both sides carry one it decides the answer by itself.
        if let bundleIdentifier = Self.normalized(bundleIdentifier),
           let otherBundleIdentifier = Self.normalized(runningApplication.bundleIdentifier) {
            return bundleIdentifier.caseInsensitiveCompare(otherBundleIdentifier) == .orderedSame
        }

        // Falling back to the name is only safe when neither side has a bundle identifier. Two apps
        // that both report one and disagree are different apps, whatever they happen to be called.
        guard Self.normalized(bundleIdentifier) == nil,
              Self.normalized(runningApplication.bundleIdentifier) == nil else {
            return false
        }

        return Self.foldedName(name) == Self.foldedName(runningApplication.name)
    }

    /// Whether any of these running applications is this guarded application.
    func isRunning(among runningApplications: [RunningApplication]) -> Bool {
        runningApplications.contains { matches($0) }
    }

    /// Trims a field and treats a blank one as absent, so whitespace never counts as an identity.
    private static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }

    /// Normalizes a name for comparison so case, accents and stray spaces do not split one app in two.
    private static func foldedName(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}
