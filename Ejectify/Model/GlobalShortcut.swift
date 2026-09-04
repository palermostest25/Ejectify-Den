//
//  GlobalShortcut.swift
//  Ejectify
//
//  Created by Codex on 04/09/2026.
//

import AppKit
import Carbon

/// A user-configurable global keyboard shortcut, stored as a Carbon key code and modifier mask.
struct GlobalShortcut: Codable, Hashable, Sendable {

    /// Virtual key code, matching Carbon's `kVK_` constants.
    var keyCode: UInt32

    /// Carbon modifier mask, built from `cmdKey`, `shiftKey`, `optionKey` and `controlKey`.
    var carbonModifiers: UInt32

    /// Actions that can be bound to a global shortcut.
    enum Action: String, CaseIterable, Sendable {
        case unmountAll
        case mountAll

        /// Shortcut used until the user changes it.
        var defaultShortcut: GlobalShortcut {
            switch self {
            case .unmountAll:
                GlobalShortcut(keyCode: UInt32(kVK_ANSI_E), carbonModifiers: UInt32(cmdKey | shiftKey))
            case .mountAll:
                GlobalShortcut(keyCode: UInt32(kVK_ANSI_M), carbonModifiers: UInt32(cmdKey | shiftKey))
            }
        }

        /// Carbon hotkey identifier, which must be stable and unique per action.
        var hotKeyID: UInt32 {
            switch self {
            case .unmountAll: 1
            case .mountAll: 2
            }
        }
    }

    /// Creates a shortcut from AppKit values captured while recording.
    init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    /// Creates a shortcut from a recorded key event, or `nil` when it carries no usable modifier.
    init?(event: NSEvent) {
        let carbonModifiers = Self.carbonModifiers(from: event.modifierFlags)

        // A shortcut without Command or Control would swallow ordinary typing system-wide.
        guard carbonModifiers & UInt32(cmdKey | controlKey) != 0 else {
            return nil
        }

        self.init(keyCode: UInt32(event.keyCode), carbonModifiers: carbonModifiers)
    }

    /// Human-readable form such as "⇧⌘E", using Apple's modifier order.
    var displayString: String {
        var symbols = ""
        if carbonModifiers & UInt32(controlKey) != 0 { symbols += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { symbols += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { symbols += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { symbols += "⌘" }
        return symbols + (Self.keyNames[keyCode] ?? String(localized: "Key \(Int(keyCode))"))
    }

    /// AppKit modifier flags, used for menu item key equivalents.
    var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbonModifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if carbonModifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbonModifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if carbonModifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        return flags
    }

    /// Key equivalent for a menu item, empty when AppKit has no character for the key.
    var menuKeyEquivalent: String {
        Self.menuKeyEquivalents[keyCode] ?? ""
    }

    /// Converts AppKit modifier flags into a Carbon modifier mask.
    static func carbonModifiers(from modifierFlags: NSEvent.ModifierFlags) -> UInt32 {
        var carbonModifiers: UInt32 = 0
        if modifierFlags.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if modifierFlags.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if modifierFlags.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
        if modifierFlags.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        return carbonModifiers
    }

    /// Characters AppKit expects in `NSMenuItem.keyEquivalent`, which are not the glyphs used for display.
    private static let menuKeyEquivalents: [UInt32: String] = {
        var equivalents: [UInt32: String] = [
            UInt32(kVK_Space): " ",
            UInt32(kVK_Return): "\r",
            UInt32(kVK_Tab): "\t",
            UInt32(kVK_Escape): "\u{1B}",
            UInt32(kVK_Delete): "\u{8}",
            UInt32(kVK_ForwardDelete): "\u{7F}",
            UInt32(kVK_LeftArrow): String(UnicodeScalar(UInt16(NSLeftArrowFunctionKey))!),
            UInt32(kVK_RightArrow): String(UnicodeScalar(UInt16(NSRightArrowFunctionKey))!),
            UInt32(kVK_UpArrow): String(UnicodeScalar(UInt16(NSUpArrowFunctionKey))!),
            UInt32(kVK_DownArrow): String(UnicodeScalar(UInt16(NSDownArrowFunctionKey))!)
        ]

        // Letters and digits are their own key equivalents, lowercased as AppKit expects.
        for (keyCode, keyName) in keyNames where keyName.count == 1 && keyName.rangeOfCharacter(from: .alphanumerics) != nil {
            equivalents[keyCode] = keyName.lowercased()
        }

        let functionKeyCodes = [
            kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6,
            kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12
        ]
        for (index, keyCode) in functionKeyCodes.enumerated() {
            equivalents[UInt32(keyCode)] = String(UnicodeScalar(UInt16(NSF1FunctionKey + index))!)
        }

        return equivalents
    }()

    /// Display names for the key codes a shortcut is likely to use.
    private static let keyNames: [UInt32: String] = {
        var names: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
            UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
            UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
            UInt32(kVK_ANSI_9): "9",
            UInt32(kVK_Space): "␣", UInt32(kVK_Return): "↩", UInt32(kVK_Escape): "⎋",
            UInt32(kVK_Delete): "⌫", UInt32(kVK_ForwardDelete): "⌦", UInt32(kVK_Tab): "⇥",
            UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→",
            UInt32(kVK_UpArrow): "↑", UInt32(kVK_DownArrow): "↓"
        ]

        let functionKeyCodes = [
            kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6,
            kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12
        ]
        for (index, keyCode) in functionKeyCodes.enumerated() {
            names[UInt32(keyCode)] = "F\(index + 1)"
        }

        return names
    }()
}
