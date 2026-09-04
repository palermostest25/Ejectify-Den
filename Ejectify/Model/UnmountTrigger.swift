//
//  UnmountTrigger.swift
//  Ejectify
//
//  Created by Codex on 04/09/2026.
//

import Foundation

/// Defines which system events trigger automatic unmounting. Raw values are persisted and must stay stable.
enum UnmountTrigger: String, CaseIterable, Sendable {
    case systemStartsSleeping = "systemStartsSleeping"
    case screensStartedSleeping = "screensStartedSleeping"
    case screenIsLocked = "screenIsLocked"
    case screensaverStarted = "screensaverStarted"
    case dockDisconnected = "dockDisconnected"
    case externalDisplayDisconnected = "externalDisplayDisconnected"

    /// Trigger used for new installs and whenever a stored selection cannot be used.
    static let legacyDefault = UnmountTrigger.systemStartsSleeping

    /// Creates a trigger value from persisted defaults, including restored Ejectify 1 trigger values.
    init(persistedRawValue: String?) {
        guard let persistedRawValue, let trigger = UnmountTrigger(rawValue: persistedRawValue) else {
            self = .legacyDefault
            return
        }

        self = trigger
    }
}
