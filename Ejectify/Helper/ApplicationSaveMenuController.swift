//
//  ApplicationSaveMenuController.swift
//  Ejectify
//
//  Created by Codex on 10/09/2026.
//

import ApplicationServices

/// Asks an application to save by pressing its own Save menu item through the Accessibility API.
///
/// Pressing the app's own item beats synthesizing a Command-S keystroke: the item is found without
/// knowing the user's language, its enabled state already says whether anything needs saving, and
/// watching it settle back to disabled is the application confirming the save itself. No macOS API
/// can make another process save, so this is the only route that works across applications.
enum ApplicationSaveMenuController {

    /// What happened when an application was asked to save.
    enum Outcome: Sendable, Equatable {

        /// A Save item exists and is disabled, so there is nothing unsaved.
        case nothingToSave

        /// Save was pressed and the item settled back to disabled.
        case saved

        /// Save was pressed but never settled, usually a Save As sheet or another modal in the way.
        case didNotSettle

        /// The application exposes no Save command, so saving is not something it can be asked to do.
        case unsupported

        /// Accessibility access has not been granted, without which no menu can be read.
        case notPermitted
    }

    /// Accessibility attribute names, spelled out because they are the wire format the AX API uses.
    ///
    /// These match the `kAXMenuBarAttribute`, `kAXChildrenAttribute`, `kAXEnabledAttribute`,
    /// `kAXMenuItemCmdCharAttribute` and `kAXMenuItemCmdModifiersAttribute` constants.
    private static let menuBarAttribute = "AXMenuBar"
    private static let childrenAttribute = "AXChildren"
    private static let enabledAttribute = "AXEnabled"
    private static let commandCharacterAttribute = "AXMenuItemCmdChar"
    private static let commandModifiersAttribute = "AXMenuItemCmdModifiers"
    private static let pressAction = "AXPress"

    /// Seconds to wait for any single Accessibility request, so a wedged application cannot hang a
    /// sleep transition while Ejectify waits for an answer that is never coming.
    private static let messagingTimeoutSeconds: Float = 2

    /// How often the Save item is re-read while waiting for it to settle.
    private static let pollInterval = Duration.milliseconds(200)

    /// Whether Ejectify may read other applications' menus at all.
    static var isPermitted: Bool {
        AXIsProcessTrusted()
    }

    /// Asks the application with this process identifier to save, and reports what happened.
    ///
    /// Runs off the main actor because every Accessibility call is a round trip into another
    /// process; the element handles never leave this function.
    static func save(processIdentifier: pid_t, timeout: Duration) async -> Outcome {
        guard isPermitted else {
            return .notPermitted
        }

        let application = AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetMessagingTimeout(application, messagingTimeoutSeconds)

        guard let saveItem = findSaveItem(in: application) else {
            return .unsupported
        }

        guard isEnabled(saveItem) else {
            return .nothingToSave
        }

        guard AXUIElementPerformAction(saveItem, pressAction as CFString) == .success else {
            return .didNotSettle
        }

        return await waitUntilSettled(saveItem, timeout: timeout) ? .saved : .didNotSettle
    }

    /// Waits for the Save item to become disabled, which is the application reporting nothing left to save.
    private static func waitUntilSettled(_ saveItem: AXUIElement, timeout: Duration) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)

        while ContinuousClock.now < deadline {
            do {
                try await Task.sleep(for: pollInterval)
            } catch {
                return false
            }

            if !isEnabled(saveItem) {
                return true
            }
        }

        return false
    }

    /// Finds the menu item bound to Command-S anywhere in the menu bar.
    ///
    /// Matching on the shortcut rather than the title "Save" keeps this working in every language.
    /// The whole menu bar is searched rather than the File menu, because identifying the File menu
    /// would mean matching its title, which is exactly the localized comparison being avoided.
    private static func findSaveItem(in application: AXUIElement) -> AXUIElement? {
        guard let menuBar = copyElement(application, attribute: menuBarAttribute) else {
            return nil
        }

        // A menu bar holds top-level items, each of which owns the menu that holds the commands.
        for topLevelItem in copyElements(menuBar, attribute: childrenAttribute) ?? [] {
            for menu in copyElements(topLevelItem, attribute: childrenAttribute) ?? [] {
                for item in copyElements(menu, attribute: childrenAttribute) ?? [] where isSaveCommand(item) {
                    return item
                }
            }
        }

        return nil
    }

    /// Whether a menu item is bound to Command-S with no additional modifier.
    private static func isSaveCommand(_ item: AXUIElement) -> Bool {
        guard let character = copyValue(item, attribute: commandCharacterAttribute) as? String,
              character.caseInsensitiveCompare("s") == .orderedSame else {
            return false
        }

        // Zero means Command alone; other bits mean Shift, Option or Control joined it, which makes
        // the item something else entirely, such as Save As or Save a Copy.
        guard let modifiers = copyValue(item, attribute: commandModifiersAttribute) as? Int, modifiers == 0 else {
            return false
        }

        return true
    }

    /// Whether a menu item is currently enabled, treating an unreadable item as disabled.
    private static func isEnabled(_ element: AXUIElement) -> Bool {
        copyValue(element, attribute: enabledAttribute) as? Bool ?? false
    }

    /// Reads one attribute, returning nil for any Accessibility error.
    private static func copyValue(_ element: AXUIElement, attribute: String) -> Any? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }

        return value
    }

    /// Reads an attribute holding a single element, checking the Core Foundation type before casting.
    private static func copyElement(_ element: AXUIElement, attribute: String) -> AXUIElement? {
        guard let value = copyValue(element, attribute: attribute) as CFTypeRef?,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }

        return (value as! AXUIElement)
    }

    /// Reads an attribute holding a list of elements, dropping anything that is not one.
    private static func copyElements(_ element: AXUIElement, attribute: String) -> [AXUIElement]? {
        guard let values = copyValue(element, attribute: attribute) as? [CFTypeRef] else {
            return nil
        }

        return values.compactMap { value in
            guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
                return nil
            }

            return (value as! AXUIElement)
        }
    }
}
