//
//  RunningApplicationProbe.swift
//  Ejectify
//
//  Created by Codex on 08/09/2026.
//

import AppKit

/// Snapshot of one running application, so guard decisions can be made and tested without AppKit.
struct RunningApplication: Hashable, Sendable {

    /// Bundle identifier reported by macOS, absent for a process that has none.
    let bundleIdentifier: String?

    /// Name as macOS presents it to the user.
    let name: String

    /// Whether the app appears in the Dock and app switcher, as opposed to running as a background agent.
    let isUserFacing: Bool
}

/// Reads the applications macOS currently reports as running in the user's session.
enum RunningApplicationProbe {

    /// Every running application, background agents included, so a guarded app is found wherever it hides.
    static func runningApplications() -> [RunningApplication] {
        NSWorkspace.shared.runningApplications.compactMap { application in
            guard !application.isTerminated else {
                return nil
            }

            // localizedName is absent for some background processes, so fall back to the file name
            // macOS launched, which is the only other thing a user could recognize.
            let name = application.localizedName
                ?? application.bundleURL?.deletingPathExtension().lastPathComponent
                ?? application.executableURL?.lastPathComponent

            guard let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }

            return RunningApplication(
                bundleIdentifier: application.bundleIdentifier,
                name: name,
                isUserFacing: application.activationPolicy == .regular
            )
        }
    }
}
