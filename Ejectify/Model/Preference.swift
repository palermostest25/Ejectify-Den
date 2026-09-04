//
//  Preference.swift
//  Ejectify
//
//  Created by Niels Mouthaan on 27/11/2020.
//

import Foundation
import LaunchAtLogin

/// Centralizes persisted user preferences used by Ejectify.
enum Preference {


    /// Events that can trigger automatic unmounting, kept under the historical `Preference.UnmountWhen` name.
    typealias UnmountWhen = UnmountTrigger

    /// Controls whether Ejectify launches automatically at user login.
    static var launchAtLogin: Bool {
        get {
            return LaunchAtLogin.isEnabled
        }
        set {
            LaunchAtLogin.isEnabled = newValue
            Log.preferences.log("Preference changed: launchAtLogin=\(newValue)")
        }
    }

    /// Controls which events trigger automatic unmounting. Never empty; an empty selection is rejected.
    static var unmountWhen: Set<UnmountWhen> {
        get {
            UnmountTriggersPreference.value(in: .standard)
        }
        set {
            guard UnmountTriggersPreference.set(newValue, in: .standard) else {
                return
            }

            Log.preferences.log("Preference changed: unmountWhen=\(UnmountTriggersPreference.sortedRawValues(of: newValue).joined(separator: ","))")
            restartMonitoring()
        }
    }

    /// Adapters the user marked as docks. Losing one of these fires the dock disconnected trigger.
    static var rememberedDocks: [PowerAdapterIdentity] {
        get {
            RememberedDocksPreference.value(in: .standard)
        }
        set {
            RememberedDocksPreference.set(newValue, in: .standard)
            Log.preferences.log("Preference changed: rememberedDocks=\(newValue.count)")
            restartMonitoring()
        }
    }

    /// Controls whether automatic remount passes are skipped while the Mac runs on battery power.
    static var keepUnmountedOnBattery: Bool {
        get {
            UserDefaults.standard.bool(forKey: "preference.keepUnmountedOnBattery")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "preference.keepUnmountedOnBattery")
            Log.preferences.log("Preference changed: keepUnmountedOnBattery=\(newValue)")
            restartMonitoring()
        }
    }

    /// Controls whether unmount requests, including eject preparation, should use the force option.
    static var forceUnmount: Bool {
        get {
            return UserDefaults.standard.bool(forKey: "preference.forceUnmount")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "preference.forceUnmount")
            Log.preferences.log("Preference changed: forceUnmount=\(newValue)")
        }
    }

    /// Controls whether Ejectify may use its own saved credentials or password prompt to unlock volumes.
    static var unlockVolumesWhenNeeded: Bool {
        get {
            UnlockVolumesWhenNeededPreference.value(in: .standard)
        }
        set {
            UnlockVolumesWhenNeededPreference.set(newValue, in: .standard)
            Log.preferences.log("Preference changed: unlockVolumesWhenNeeded=\(newValue)")
        }
    }

    /// Controls whether automatic and manual disk handling ejects whole disks instead of unmounting volumes.
    static var ejectInsteadOfUnmount: Bool {
        get {
            UserDefaults.standard.bool(forKey: "preference.ejectInsteadOfUnmount")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "preference.ejectInsteadOfUnmount")
            Log.preferences.log("Preference changed: ejectInsteadOfUnmount=\(newValue)")

            guard newValue else {
                return
            }

            Task { @MainActor in
                AppDelegate.shared.activityController?.clearRemountStateForEjectMode()
            }
        }
    }

    /// Re-registers activity observers so preference changes take effect immediately.
    private static func restartMonitoring() {
        Task { @MainActor in
            AppDelegate.shared.activityController?.startMonitoring()
        }
    }

    /// Tracks whether the one-time onboarding window has already been shown.
    static var hasSeenOnboarding: Bool {
        get {
            return UserDefaults.standard.bool(forKey: "preference.hasSeenOnboarding")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "preference.hasSeenOnboarding")
            Log.preferences.info("Preference changed: hasSeenOnboarding=\(newValue)")
        }
    }
}
