//
//  AppDelegate.swift
//  Ejectify
//
//  Created by Niels Mouthaan on 21/11/2020.
//

import Cocoa

@MainActor

/// Coordinates app startup and wires core menu/activity controllers.
final class AppDelegate: NSObject, NSApplicationDelegate {


    /// Shared delegate instance exposed for app-wide coordination.
    static let shared = NSApplication.shared.delegate as! AppDelegate

    /// Owns the menu bar status item and its menu lifecycle.
    var statusBar: StatusBar?

    /// Owns event observation and disk-operation orchestration.
    var activityController: ActivityController?

    /// Owns global hotkey registration and dispatch for the configured all-volumes action.
    private var globalHotKeyController: GlobalHotKeyController?

    /// Owns Sparkle updater lifecycle and manual update actions.
    private var updateController: UpdateController?

    /// Owns diagnostics report generation and export UI.
    private let diagnosticsReportController = DiagnosticsReportController()

    /// Owns the onboarding window lifecycle while guidance is presented.
    private var onboardingWindowController: OnboardingWindowController?

    /// Returns whether the global unmount-all hotkey is currently registered.
    var isUnmountAllHotKeyRegistered: Bool {
        globalHotKeyController?.isRegistered(.unmountAll) ?? false
    }

    /// Returns whether the global mount-all hotkey is currently registered.
    var isMountAllHotKeyRegistered: Bool {
        globalHotKeyController?.isRegistered(.mountAll) ?? false
    }

    /// Returns whether the global unmount-and-sleep hotkey is currently registered.
    var isUnmountAllAndSleepHotKeyRegistered: Bool {
        globalHotKeyController?.isRegistered(.unmountAllAndSleep) ?? false
    }

    /// Owns the window used to change global keyboard shortcuts.
    private var shortcutSettingsWindowController: ShortcutSettingsWindowController?

    /// Re-registers global hotkeys after the user changes a shortcut.
    func reloadGlobalShortcuts() {
        globalHotKeyController?.reloadShortcuts()
    }

    /// Presents the window for changing global keyboard shortcuts.
    func showShortcutSettings() {
        if shortcutSettingsWindowController == nil {
            shortcutSettingsWindowController = ShortcutSettingsWindowController { [weak self] in
                self?.shortcutSettingsWindowController = nil
            }
        }

        shortcutSettingsWindowController?.showCentered()
    }

    /// Bootstraps routing mode, applies one-time first-run setup, and initializes primary app controllers.
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let isFirstLaunch = !Preference.hasSeenOnboarding
        VolumeOperationRouter.shared.configureExecutionMode()

        if isFirstLaunch {
            Preference.launchAtLogin = true

            // First launch is the only automatic registration attempt so macOS can surface helper approval once; later retries only happen after explicit user action.
            VolumeOperationRouter.shared.requestPrivilegedExecutionMode()
        }

        globalHotKeyController = GlobalHotKeyController { [weak self] action in
            switch action {
            case .unmountAll:
                self?.performManualUnmountAll()
            case .mountAll:
                self?.activityController?.performManualMountPass()
            case .unmountAllAndSleep:
                self?.activityController?.performManualUnmountAndSleep()
            }
        }
        statusBar = StatusBar()
        activityController = ActivityController()
        let updateController = UpdateController()
        self.updateController = updateController
        updateController.start()

        if isFirstLaunch {
            showOnboarding()
        }
    }

    /// Starts a user-initiated Sparkle update check.
    func checkForUpdates() {
        updateController?.checkForUpdates()
    }

    /// Starts a user-initiated diagnostics report save flow.
    func saveDiagnosticsReport() {
        diagnosticsReportController.saveDiagnosticsReport()
    }

    /// Handles all enabled volumes using the configured user-initiated action.
    func performManualUnmountAll() {
        // Routing the manual action through the activity controller keeps remount tracking, progress
        // reporting and unmount verification identical to the automatic triggers.
        guard let activityController else {
            Log.app.error("Manual unmount-all skipped; reason=activity controller unavailable")
            return
        }

        activityController.performManualAllVolumesAction()
    }

    /// Sends a best-effort helper shutdown request when the app is quitting.
    func applicationWillTerminate(_ notification: Notification) {
        VolumeOperationRouter.shared.requestHelperTermination()
    }

    /// Presents the onboarding window.
    private func showOnboarding() {
        onboardingWindowController = OnboardingWindowController { [weak self] in
            self?.onboardingWindowController = nil
        }
        onboardingWindowController?.showCentered()
    }
}
