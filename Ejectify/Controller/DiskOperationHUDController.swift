//
//  DiskOperationHUDController.swift
//  Ejectify
//
//  Created by Codex on 04/09/2026.
//

import AppKit
import SwiftUI

/// Presents the disk operation progress panel beneath the status bar icon.
@MainActor
final class DiskOperationHUDController {

    /// Shared controller used by every disk-operation entry point.
    static let shared = DiskOperationHUDController()

    /// Panel hosting the progress view, created on first use.
    private var panel: NSPanel?

    /// Invoked when the user asks for the applications holding a disk open to be quit and the
    /// operation tried again. Set once at start-up by whatever owns disk operations.
    var onQuitAndRetry: (([GuardedApplication]) -> Void)?

    /// Pending automatic dismissal for a successful batch.
    private var dismissTask: Task<Void, Never>?

    /// How long a fully successful batch stays on screen.
    private static let successDismissDelay: Duration = .milliseconds(1800)

    /// Distance between the status item and the top of the panel.
    private static let panelGap: CGFloat = 6

    /// Starts reporting a batch and shows the panel.
    func begin(kind: DiskOperationProgress.Kind, volumes: [(id: String, name: String)]) {
        guard !volumes.isEmpty else {
            return
        }

        dismissTask?.cancel()
        dismissTask = nil
        DiskOperationProgress.shared.begin(kind: kind, volumes: volumes)
        show()
    }

    /// Records one volume's outcome and dismisses the panel once a successful batch completes.
    func finish(volumeID: String, state: DiskOperationProgress.RowState) {
        let progress = DiskOperationProgress.shared
        guard progress.isActive else {
            return
        }

        progress.finish(volumeID: volumeID, state: state)

        guard progress.isFinished else {
            return
        }

        // A failure stays on screen until dismissed, so an unmount that did not happen cannot be missed.
        guard !progress.hasFailure else {
            positionPanel()
            return
        }

        scheduleDismiss()
    }

    /// Names what is holding a failed volume open, once the answer arrives.
    func describeFailure(volumeID: String, reason: String, quittableApplications: [GuardedApplication]) {
        let progress = DiskOperationProgress.shared
        guard progress.isActive else {
            return
        }

        progress.describeFailure(volumeID: volumeID, reason: reason)
        progress.addQuittableApplications(quittableApplications)
        positionPanel()
    }

    /// Quits the applications holding the batch's disks open and tries again.
    func quitBlockingApplicationsAndRetry() {
        let applications = DiskOperationProgress.shared.quittableApplications
        guard !applications.isEmpty, let onQuitAndRetry else {
            return
        }

        dismiss()
        onQuitAndRetry(applications)
    }

    /// Drops a volume from the batch when its operation ended without an outcome to report.
    ///
    /// A deferred remount is not a failure, so the row leaves rather than turning red, and a batch
    /// left with no rows dismisses instead of sitting on screen at "running" forever.
    func cancel(volumeID: String) {
        let progress = DiskOperationProgress.shared
        guard progress.isActive, progress.remove(volumeID: volumeID) else {
            return
        }

        // At default level on purpose: a panel that would not go away is exactly the symptom
        // this explains, and an info-level line is hidden unless `log show` is asked for it.
        Log.volumeOperations.log("Progress row dropped without an outcome; remaining=\(progress.totalCount)")

        guard !progress.rows.isEmpty else {
            dismiss()
            return
        }

        guard progress.isFinished else {
            return
        }

        guard !progress.hasFailure else {
            positionPanel()
            return
        }

        scheduleDismiss()
    }

    /// Hides the panel and clears the batch.
    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        panel?.orderOut(nil)
        DiskOperationProgress.shared.clear()
    }

    /// Creates the panel on first use and brings it on screen.
    private func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        positionPanel()
        panel.orderFrontRegardless()
    }

    /// Builds the borderless, non-activating panel that hosts the SwiftUI view.
    private func makePanel() -> NSPanel {
        let hostingController = NSHostingController(
            rootView: DiskOperationHUDView(
                progress: DiskOperationProgress.shared,
                onDismiss: { [weak self] in
                    self?.dismiss()
                },
                onQuitAndRetry: { [weak self] in
                    self?.quitBlockingApplicationsAndRetry()
                }
            )
        )

        let panel = NonActivatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 276, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hostingController
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return panel
    }

    /// Anchors the panel under the status item, keeping it on screen.
    private func positionPanel() {
        guard let panel else {
            return
        }

        // Let the hosting controller settle first so the panel is sized to its content.
        panel.layoutIfNeeded()
        let panelSize = panel.frame.size

        guard let anchorFrame = statusItemScreenFrame(),
              let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchorFrame) }) ?? NSScreen.main else {
            return
        }

        var origin = NSPoint(
            x: anchorFrame.midX - panelSize.width / 2,
            y: anchorFrame.minY - Self.panelGap - panelSize.height
        )

        // Keep the panel fully inside the screen that owns the status item.
        let visibleFrame = screen.visibleFrame
        origin.x = min(max(origin.x, visibleFrame.minX + 8), visibleFrame.maxX - panelSize.width - 8)
        origin.y = max(origin.y, visibleFrame.minY + 8)
        panel.setFrameOrigin(origin)
    }

    /// Returns the status item button's frame in screen coordinates.
    private func statusItemScreenFrame() -> NSRect? {
        guard let button = AppDelegate.shared.statusBar?.button,
              let window = button.window else {
            return nil
        }

        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    /// Dismisses a successful batch after a short delay.
    private func scheduleDismiss() {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: DiskOperationHUDController.successDismissDelay)
            } catch {
                return
            }

            guard let self else {
                return
            }

            self.dismissTask = nil
            self.dismiss()
        }
    }
}

/// Panel that accepts clicks without pulling the menu bar app to the foreground.
private final class NonActivatingPanel: NSPanel {

    /// Allows the panel's controls to be clicked while another app stays active.
    override var canBecomeKey: Bool {
        true
    }
}
