//
//  GlobalShortcutTests.swift
//  EjectifyTests
//
//  Created by Codex on 04/09/2026.
//

import AppKit
import Carbon
import Foundation
import Testing

struct GlobalShortcutTests {

    @Test func defaultsMatchTheDocumentedShortcuts() {
        let unmountAll = GlobalShortcut.Action.unmountAll.defaultShortcut
        let mountAll = GlobalShortcut.Action.mountAll.defaultShortcut

        #expect(unmountAll.displayString == "⇧⌘E")
        #expect(mountAll.displayString == "⇧⌘M")
        #expect(GlobalShortcut.Action.unmountAllAndSleep.defaultShortcut.displayString == "⇧⌘S")

        // No two actions may ship with the same default, or one could never register.
        let defaults = GlobalShortcut.Action.allCases.map(\.defaultShortcut)
        #expect(Set(defaults).count == defaults.count)
    }

    @Test func actionsHaveDistinctHotKeyIdentifiers() {
        let identifiers = GlobalShortcut.Action.allCases.map(\.hotKeyID)

        #expect(Set(identifiers).count == identifiers.count)
    }

    @Test func modifierSymbolsFollowAppleOrder() {
        let shortcut = GlobalShortcut(
            keyCode: UInt32(kVK_ANSI_E),
            carbonModifiers: UInt32(cmdKey | shiftKey | optionKey | controlKey)
        )

        #expect(shortcut.displayString == "⌃⌥⇧⌘E")
    }

    @Test func modifierFlagsRoundTripThroughCarbon() {
        let flags: NSEvent.ModifierFlags = [.command, .shift]
        let carbonModifiers = GlobalShortcut.carbonModifiers(from: flags)
        let shortcut = GlobalShortcut(keyCode: UInt32(kVK_ANSI_E), carbonModifiers: carbonModifiers)

        #expect(shortcut.modifierFlags == flags)
    }

    @Test func menuKeyEquivalentUsesCharactersAppKitUnderstands() {
        #expect(GlobalShortcut(keyCode: UInt32(kVK_ANSI_E), carbonModifiers: UInt32(cmdKey)).menuKeyEquivalent == "e")
        #expect(GlobalShortcut(keyCode: UInt32(kVK_ANSI_7), carbonModifiers: UInt32(cmdKey)).menuKeyEquivalent == "7")

        // The display glyph and the key equivalent are different things: "␣" draws, " " triggers.
        #expect(GlobalShortcut(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(cmdKey)).displayString == "⌘␣")
        #expect(GlobalShortcut(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(cmdKey)).menuKeyEquivalent == " ")

        let leftArrow = GlobalShortcut(keyCode: UInt32(kVK_LeftArrow), carbonModifiers: UInt32(cmdKey))
        #expect(leftArrow.displayString == "⌘←")
        #expect(leftArrow.menuKeyEquivalent == String(UnicodeScalar(UInt16(NSLeftArrowFunctionKey))!))

        let functionKey = GlobalShortcut(keyCode: UInt32(kVK_F5), carbonModifiers: UInt32(cmdKey))
        #expect(functionKey.menuKeyEquivalent == String(UnicodeScalar(UInt16(NSF5FunctionKey))!))

        // An unmapped key contributes no menu key equivalent at all.
        #expect(GlobalShortcut(keyCode: 999, carbonModifiers: UInt32(cmdKey)).menuKeyEquivalent == "")
    }

    @Test func functionKeysAreNamed() {
        #expect(GlobalShortcut(keyCode: UInt32(kVK_F5), carbonModifiers: UInt32(cmdKey)).displayString == "⌘F5")
    }

    @Test func codableRoundTripPreservesTheShortcut() throws {
        let shortcut = GlobalShortcut(keyCode: UInt32(kVK_ANSI_E), carbonModifiers: UInt32(cmdKey | shiftKey))

        let decoded = try JSONDecoder().decode(GlobalShortcut.self, from: JSONEncoder().encode(shortcut))

        #expect(decoded == shortcut)
    }

    @Test func storedShortcutsFallBackToDefaults() {
        let (userDefaults, suiteName) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        #expect(GlobalShortcutPreference.value(for: .unmountAll, in: userDefaults) == GlobalShortcut.Action.unmountAll.defaultShortcut)

        let custom = GlobalShortcut(keyCode: UInt32(kVK_ANSI_J), carbonModifiers: UInt32(cmdKey | controlKey))
        GlobalShortcutPreference.set(custom, for: .unmountAll, in: userDefaults)
        #expect(GlobalShortcutPreference.value(for: .unmountAll, in: userDefaults) == custom)

        GlobalShortcutPreference.set(nil, for: .unmountAll, in: userDefaults)
        #expect(GlobalShortcutPreference.value(for: .unmountAll, in: userDefaults) == GlobalShortcut.Action.unmountAll.defaultShortcut)
    }

    @Test func aShortcutBoundToAnotherActionIsReportedAsAConflict() {
        let (userDefaults, suiteName) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let mountAllDefault = GlobalShortcut.Action.mountAll.defaultShortcut

        #expect(GlobalShortcutPreference.conflictingAction(with: mountAllDefault, excluding: .unmountAll, in: userDefaults) == .mountAll)
        #expect(GlobalShortcutPreference.conflictingAction(with: mountAllDefault, excluding: .mountAll, in: userDefaults) == nil)
    }

    @Test func unreadableStoredShortcutFallsBackToTheDefault() {
        let (userDefaults, suiteName) = makeIsolatedDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        userDefaults.set(Data("not json".utf8), forKey: GlobalShortcutPreference.key(for: .mountAll))

        #expect(GlobalShortcutPreference.value(for: .mountAll, in: userDefaults) == GlobalShortcut.Action.mountAll.defaultShortcut)
    }

    /// Creates a unique defaults suite so tests never modify the app's actual preferences.
    private func makeIsolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "GlobalShortcutTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return (userDefaults, suiteName)
    }
}
