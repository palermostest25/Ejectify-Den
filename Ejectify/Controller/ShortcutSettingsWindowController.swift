//
//  ShortcutSettingsWindowController.swift
//  Ejectify
//
//  Created by Codex on 04/09/2026.
//

import AppKit
import Carbon

/// Presents the window used to change the app-wide keyboard shortcuts.
@MainActor
final class ShortcutSettingsWindowController: NSWindowController, NSWindowDelegate {

    /// Callback invoked after the window has closed.
    private let onWindowWillClose: () -> Void

    /// Recorder controls keyed by the action they configure.
    private var recorders: [GlobalShortcut.Action: ShortcutRecorderButton] = [:]

    /// Builds the window and its rows, one per configurable action.
    init(onWindowWillClose: @escaping () -> Void = {}) {
        self.onWindowWillClose = onWindowWillClose

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 150),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Keyboard Shortcuts")

        super.init(window: window)

        window.delegate = self
        window.contentView = makeContentView()
    }

    /// Storyboard initialization is unsupported because this controller is built in code.
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Shows the window centered and brings it to the foreground.
    func showCentered() {
        guard let window else {
            return
        }

        refreshRecorderTitles()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    /// Releases the controller after the window has closed.
    func windowWillClose(_ notification: Notification) {
        for recorder in recorders.values {
            recorder.cancelRecording()
        }

        onWindowWillClose()
    }

    /// Builds the stack of shortcut rows plus the explanatory footer.
    private func makeContentView() -> NSView {
        let rowsStackView = NSStackView(views: GlobalShortcut.Action.allCases.map(makeRow(for:)))
        rowsStackView.orientation = .vertical
        rowsStackView.alignment = .leading
        rowsStackView.spacing = 10

        let footerLabel = NSTextField(labelWithString: String(localized: "Click a shortcut, then press the new key combination."))
        footerLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        footerLabel.textColor = .secondaryLabelColor

        let contentStackView = NSStackView(views: [rowsStackView, footerLabel])
        contentStackView.orientation = .vertical
        contentStackView.alignment = .leading
        contentStackView.spacing = 16
        contentStackView.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        contentStackView.translatesAutoresizingMaskIntoConstraints = false

        let containerView = NSView()
        containerView.addSubview(contentStackView)
        NSLayoutConstraint.activate([
            contentStackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            contentStackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            contentStackView.topAnchor.constraint(equalTo: containerView.topAnchor),
            contentStackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        return containerView
    }

    /// Builds one labelled row with its recorder and reset control.
    private func makeRow(for action: GlobalShortcut.Action) -> NSView {
        let label = NSTextField(labelWithString: title(for: action))
        label.alignment = .right
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.widthAnchor.constraint(equalToConstant: 150).isActive = true

        let recorder = ShortcutRecorderButton(action: action) { [weak self] recordedShortcut in
            self?.apply(recordedShortcut, to: action)
        }
        recorder.widthAnchor.constraint(equalToConstant: 140).isActive = true
        recorders[action] = recorder

        let resetButton = NSButton(title: String(localized: "Reset"), target: self, action: #selector(resetClicked(_:)))
        resetButton.bezelStyle = .rounded
        resetButton.controlSize = .small
        resetButton.tag = Int(action.hotKeyID)

        let rowStackView = NSStackView(views: [label, recorder, resetButton])
        rowStackView.orientation = .horizontal
        rowStackView.alignment = .centerY
        rowStackView.spacing = 8
        return rowStackView
    }

    /// Returns the user-facing name of an action.
    private func title(for action: GlobalShortcut.Action) -> String {
        switch action {
        case .unmountAll:
            Preference.ejectInsteadOfUnmount ? String(localized: "Eject all") : String(localized: "Unmount all")
        case .mountAll:
            String(localized: "Mount all")
        case .unmountAllAndSleep:
            String(localized: "Unmount all and sleep")
        }
    }

    /// Stores a newly recorded shortcut unless another action already uses it.
    private func apply(_ shortcut: GlobalShortcut, to action: GlobalShortcut.Action) {
        if let conflictingAction = Preference.actionConflicting(with: shortcut, excluding: action) {
            showConflictAlert(shortcut: shortcut, conflictingAction: conflictingAction)
            refreshRecorderTitles()
            return
        }

        Preference.setShortcut(shortcut, for: action)
        refreshRecorderTitles()
    }

    /// Restores one action's default shortcut.
    @objc private func resetClicked(_ sender: NSButton) {
        guard let action = GlobalShortcut.Action.allCases.first(where: { Int($0.hotKeyID) == sender.tag }) else {
            return
        }

        Preference.setShortcut(nil, for: action)
        refreshRecorderTitles()
    }

    /// Warns that a shortcut is already bound to another action.
    private func showConflictAlert(shortcut: GlobalShortcut, conflictingAction: GlobalShortcut.Action) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "\(shortcut.displayString) is already used")
        alert.informativeText = String(localized: "This shortcut is assigned to \"\(title(for: conflictingAction))\". Choose a different combination.")
        alert.runModal()
    }

    /// Redraws every recorder with the shortcut currently stored for its action.
    private func refreshRecorderTitles() {
        for (action, recorder) in recorders {
            recorder.update(with: Preference.shortcut(for: action))
        }
    }
}

/// Button that displays a shortcut and captures a replacement while recording.
private final class ShortcutRecorderButton: NSButton {

    /// Action this control configures.
    private let shortcutAction: GlobalShortcut.Action

    /// Callback invoked with a newly captured shortcut.
    private let onRecord: (GlobalShortcut) -> Void

    /// Whether the control is currently waiting for a key combination.
    private var isRecording = false

    /// Creates a recorder bound to one action.
    init(action: GlobalShortcut.Action, onRecord: @escaping (GlobalShortcut) -> Void) {
        self.shortcutAction = action
        self.onRecord = onRecord
        super.init(frame: .zero)

        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        self.action = #selector(startRecording)
        update(with: Preference.shortcut(for: action))
    }

    /// Storyboard initialization is unsupported because this control is built in code.
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Accepts focus so key events reach this control while recording.
    override var acceptsFirstResponder: Bool {
        true
    }

    /// Shows the stored shortcut and leaves recording mode.
    func update(with shortcut: GlobalShortcut) {
        isRecording = false
        title = shortcut.displayString
    }

    /// Leaves recording mode without changing the stored shortcut.
    func cancelRecording() {
        guard isRecording else {
            return
        }

        update(with: Preference.shortcut(for: shortcutAction))
    }

    /// Enters recording mode and waits for the next key combination.
    @objc private func startRecording() {
        isRecording = true
        title = String(localized: "Press keys…")
        window?.makeFirstResponder(self)
    }

    /// Captures Command-based combinations, which arrive as key equivalents rather than key presses.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else {
            return super.performKeyEquivalent(with: event)
        }

        return capture(event)
    }

    /// Captures combinations delivered as ordinary key presses, such as Control-based ones.
    override func keyDown(with event: NSEvent) {
        guard isRecording, capture(event) else {
            super.keyDown(with: event)
            return
        }
    }

    /// Turns a key event into a shortcut, handling Escape as cancellation.
    private func capture(_ event: NSEvent) -> Bool {
        if event.keyCode == UInt16(kVK_Escape) {
            cancelRecording()
            return true
        }

        guard let shortcut = GlobalShortcut(event: event) else {
            // Without Command or Control the combination would capture ordinary typing system-wide.
            NSSound.beep()
            return true
        }

        onRecord(shortcut)
        return true
    }
}
