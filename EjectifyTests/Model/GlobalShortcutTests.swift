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
        #expect(unmountAll != mountAll)
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

    @Test func menuKeyEquivalentIsLowercasedForPrintableKeys() {
        #expect(GlobalShortcut(keyCode: UInt32(kVK_ANSI_E), carbonModifiers: UInt32(cmdKey)).menuKeyEquivalent == "e")
        // Arrow keys have no single-character equivalent, so the menu shows no key.
        #expect(GlobalShortcut(keyCode: UInt32(kVK_LeftArrow), carbonModifiers: UInt32(cmdKey)).menuKeyEquivalent == "")
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
