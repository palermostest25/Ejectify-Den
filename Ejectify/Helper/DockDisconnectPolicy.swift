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
        externalDisplayStillConnected: Bool,
        isLidClosed: Bool? = nil,
        requiresClosedLid: Bool = false
    ) -> Decision {
        guard allowsTrigger(isLidClosed: isLidClosed, requiresClosedLid: requiresClosedLid) else {
            return .ignore(reason: "lid is open")
        }

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

    /// Whether a disconnect trigger may fire at all given the lid state.
    ///
    /// With the lid open the Mac is in use, so losing a display or a charger is not a reason to pull a
    /// volume out from under whatever is writing to it. A Mac that reports no clamshell state at all is
    /// not blocked, so the trigger never disappears silently.
    static func allowsTrigger(isLidClosed: Bool?, requiresClosedLid: Bool) -> Bool {
        guard requiresClosedLid, let isLidClosed else {
            return true
        }

        return isLidClosed
    }

    /// Decides whether the Mac should be put to sleep after a trigger finished unmounting.
    static func shouldSleepAfterUnmount(
        trigger: UnmountTrigger,
        sleepAfterDockDisconnect: Bool,
        requestedCount: Int,
        succeededCount: Int
    ) -> Bool {
        guard sleepAfterDockDisconnect else {
            return false
        }

        // Only the triggers that leave the Mac awake need this; the sleep trigger would be circular.
        guard trigger == .dockDisconnected || trigger == .externalDisplayDisconnected else {
            return false
        }

        // An empty batch means another trigger unmounted everything first, which is still success.
        // Only a volume left mounted blocks sleep, so the failure stays visible.
        return succeededCount == requestedCount
    }

    /// Decides whether an automatic remount pass is allowed to run right now.
    static func remountAllowed(isOnBattery: Bool, keepUnmountedOnBattery: Bool) -> Bool {
        !(isOnBattery && keepUnmountedOnBattery)
    }
}
