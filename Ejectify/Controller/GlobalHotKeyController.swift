//
//  GlobalHotKeyController.swift
//  Ejectify
//
//  Created by Codex on 17/03/2026.
//

import Carbon
import Foundation

/// Registers and handles the app-wide keyboard shortcuts for the all-volumes actions.
final class GlobalHotKeyController {

    /// Carbon signature used to identify Ejectify's hotkey events.
    private static let hotKeySignature: OSType = 0x456A484B // ASCII for "EjHK" (Ejectify hotkey)

    /// Event specification describing the hotkey-pressed callback this controller listens for.
    private static let hotKeyPressedEvent = EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard),
        eventKind: UInt32(kEventHotKeyPressed)
    )

    /// C callback that forwards Carbon hotkey events back into the Swift controller instance.
    private static let hotKeyHandler: EventHandlerUPP = { _, eventRef, userData in
        guard let eventRef, let userData else {
            return noErr
        }

        let controller = Unmanaged<GlobalHotKeyController>.fromOpaque(userData).takeUnretainedValue()
        controller.handleHotKeyPressed(eventRef)
        return noErr
    }


    /// Action invoked when one of the registered global hotkeys is pressed.
    private let onAction: @MainActor (GlobalShortcut.Action) -> Void

    /// Registered Carbon event handler reference for hotkey press callbacks.
    private var eventHandlerRef: EventHandlerRef?

    /// Registered Carbon hotkey references, keyed by the action they trigger.
    private var hotKeyRefs: [GlobalShortcut.Action: EventHotKeyRef] = [:]

    /// Returns whether any global hotkey is currently registered.
    var isRegistered: Bool {
        !hotKeyRefs.isEmpty
    }

    /// Creates the controller, installs its event handler, and registers the configured shortcuts.
    init(onAction: @escaping @MainActor (GlobalShortcut.Action) -> Void) {
        self.onAction = onAction
        installHotKeyHandlerIfNeeded()
        reloadShortcuts()
    }

    /// Unregisters every hotkey and removes the Carbon event handler.
    deinit {
        unregisterAllHotKeys()
        removeHotKeyHandler()
    }

    /// Returns whether one action's shortcut is currently registered.
    func isRegistered(_ action: GlobalShortcut.Action) -> Bool {
        hotKeyRefs[action] != nil
    }

    /// Re-registers every action against the currently configured shortcuts.
    func reloadShortcuts() {
        unregisterAllHotKeys()

        for action in GlobalShortcut.Action.allCases {
            register(action, shortcut: Preference.shortcut(for: action))
        }
    }

    /// Installs the Carbon event handler used to receive global hotkey press events.
    private func installHotKeyHandlerIfNeeded() {
        guard eventHandlerRef == nil else {
            return
        }

        var eventHandlerRef: EventHandlerRef?
        var hotKeyPressedEvent = Self.hotKeyPressedEvent
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.hotKeyHandler,
            1,
            &hotKeyPressedEvent,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        guard status == noErr, let eventHandlerRef else {
            Log.hotKey.error("Failed to install global hotkey event handler: status=\(status)")
            return
        }

        self.eventHandlerRef = eventHandlerRef
    }

    /// Registers one action's shortcut with Carbon.
    private func register(_ action: GlobalShortcut.Action, shortcut: GlobalShortcut) {
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: action.hotKeyID)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr, let hotKeyRef else {
            // A shortcut already owned by another app is the usual cause, and the menu still offers the action.
            Log.hotKey.warning("Failed to register global hotkey; action=\(action.rawValue); status=\(status)")
            return
        }

        hotKeyRefs[action] = hotKeyRef
        Log.hotKey.log("Registered global hotkey; action=\(action.rawValue); shortcut=\(shortcut.displayString)")
    }

    /// Unregisters every currently registered hotkey.
    private func unregisterAllHotKeys() {
        for (action, hotKeyRef) in hotKeyRefs {
            let status = UnregisterEventHotKey(hotKeyRef)
            if status != noErr {
                Log.hotKey.error("Failed to unregister global hotkey; action=\(action.rawValue); status=\(status)")
            }
        }

        hotKeyRefs.removeAll()
    }

    /// Removes the Carbon event handler when the controller is torn down.
    private func removeHotKeyHandler() {
        guard let eventHandlerRef else {
            return
        }

        let status = RemoveEventHandler(eventHandlerRef)
        if status != noErr {
            Log.hotKey.error("Failed to remove global hotkey event handler: status=\(status)")
        }

        self.eventHandlerRef = nil
    }

    /// Handles an incoming Carbon hotkey event and dispatches the matching action.
    private func handleHotKeyPressed(_ eventRef: EventRef) {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            eventRef,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr else {
            Log.hotKey.error("Failed to read global hotkey event payload: status=\(status)")
            return
        }

        guard hotKeyID.signature == Self.hotKeySignature,
              let action = GlobalShortcut.Action.allCases.first(where: { $0.hotKeyID == hotKeyID.id }) else {
            return
        }

        Log.hotKey.log("Global hotkey pressed; action=\(action.rawValue)")
        Task { @MainActor [onAction] in
            onAction(action)
        }
    }
}
