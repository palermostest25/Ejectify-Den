//
//  DockDisconnectPolicy.swift
//  Ejectify
//
//  Created by Codex on 04/09/2026.
//

import Foundation

/// Decides whether losing a power adapter should unmount volumes, and whether remounting is currently allowed.
enum DockDisconnectPolicy {

    /// Outcome of evaluating one adapter-lost event.
    enum Decision: Equatable {
        case unmount(reason: String)
        case ignore(reason: String)
    }

    /// Decides whether losing `lostAdapter` should trigger an unmount.
    static func decision(
        lostAdapter: PowerAdapterIdentity?,
        rememberedDocks: [PowerAdapterIdentity],
        externalDisplayStillConnected: Bool
    ) -> Decision {
        // The reasons below are stable diagnostic strings; keep them in sync with the support documentation.
        guard let lostAdapter else {
            return .ignore(reason: "no adapter snapshot")
        }

        guard !rememberedDocks.isEmpty else {
            return .ignore(reason: "no remembered docks")
        }

        // Only remembered docks may trigger an unmount, so losing a charger such as MagSafe is ignored.
        guard lostAdapter.isRemembered(in: rememberedDocks) else {
            return .ignore(reason: "adapter not a remembered dock")
        }

        // `externalDisplayStillConnected` is reported for diagnostics only and does not change this decision yet.
        return .unmount(reason: "remembered dock lost")
    }

    /// Decides whether an automatic remount pass is allowed to run right now.
    static func remountAllowed(isOnBattery: Bool, keepUnmountedOnBattery: Bool) -> Bool {
        !(isOnBattery && keepUnmountedOnBattery)
    }
}
