//
//  ExternalDisplayObserver.swift
//  Ejectify
//
//  Created by Codex on 04/09/2026.
//

import CoreGraphics
import Foundation

/// Bridges CoreGraphics display reconfiguration callbacks to main-actor handlers for external display changes.
///
/// Call `stop()` before releasing the observer: cleanup cannot run from `deinit` because the observer is main-actor isolated.
@MainActor
final class ExternalDisplayObserver {

    /// Handler invoked when the last external display goes offline.
    private let onLastExternalDisplayDisconnected: @MainActor () -> Void

    /// Handler invoked when an external display comes online again after none were connected.
    private let onExternalDisplayConnected: @MainActor () -> Void

    /// Number of online displays that are not built into the Mac.
    private(set) var externalDisplayCount = 0

    /// Whether at least one external display is currently online.
    var hasExternalDisplay: Bool {
        externalDisplayCount > 0
    }

    /// Whether the reconfiguration callback is currently registered.
    private var isRegistered = false

    /// Pending debounced display count refresh.
    private var refreshTask: Task<Void, Never>?

    /// Time the display topology must settle before it is evaluated, because one change reports several callbacks.
    private static let debounceInterval: Duration = .milliseconds(500)

    /// Creates an observer that forwards external display transitions to the supplied handlers.
    init(
        onLastExternalDisplayDisconnected: @escaping @MainActor () -> Void,
        onExternalDisplayConnected: @escaping @MainActor () -> Void
    ) {
        self.onLastExternalDisplayDisconnected = onLastExternalDisplayDisconnected
        self.onExternalDisplayConnected = onExternalDisplayConnected
    }

    /// Registers the reconfiguration callback and seeds the current external display count.
    @discardableResult
    func start() -> Bool {
        guard !isRegistered else {
            return true
        }

        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let status = CGDisplayRegisterReconfigurationCallback(Self.reconfigurationCallback, context)
        guard status == .success else {
            Log.powerEvents.error("Failed to register for display reconfiguration callbacks; status=\(status.rawValue)")
            return false
        }

        isRegistered = true
        externalDisplayCount = Self.currentExternalDisplayCount()
        Log.powerEvents.log("External display monitoring enabled; externalDisplayCount=\(self.externalDisplayCount)")
        return true
    }

    /// Unregisters the reconfiguration callback and cancels pending evaluation.
    func stop() {
        refreshTask?.cancel()
        refreshTask = nil

        guard isRegistered else {
            return
        }

        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let status = CGDisplayRemoveReconfigurationCallback(Self.reconfigurationCallback, context)
        if status != .success {
            Log.powerEvents.warning("Failed to remove display reconfiguration callback; status=\(status.rawValue)")
        }

        isRegistered = false
        Log.powerEvents.log("External display monitoring disabled")
    }

    /// Returns the number of online displays that are not built into the Mac.
    nonisolated static func currentExternalDisplayCount() -> Int {
        var onlineDisplayCount: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &onlineDisplayCount) == .success, onlineDisplayCount > 0 else {
            return 0
        }

        var onlineDisplays = [CGDirectDisplayID](repeating: 0, count: Int(onlineDisplayCount))
        guard CGGetOnlineDisplayList(onlineDisplayCount, &onlineDisplays, &onlineDisplayCount) == .success else {
            return 0
        }

        return onlineDisplays
            .prefix(Int(onlineDisplayCount))
            .filter { CGDisplayIsBuiltin($0) == 0 }
            .count
    }

    /// Schedules one debounced evaluation of the display topology.
    private func scheduleExternalDisplayCountRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: ExternalDisplayObserver.debounceInterval)
            } catch {
                return
            }

            guard let self else {
                return
            }

            self.refreshTask = nil
            self.applyExternalDisplayCount(ExternalDisplayObserver.currentExternalDisplayCount())
        }
    }

    /// Applies a new external display count and emits the matching transition.
    private func applyExternalDisplayCount(_ newExternalDisplayCount: Int) {
        let previousExternalDisplayCount = externalDisplayCount

        guard newExternalDisplayCount != previousExternalDisplayCount else {
            return
        }

        externalDisplayCount = newExternalDisplayCount
        Log.powerEvents.info("External display topology changed; externalDisplayCount=\(newExternalDisplayCount)")

        if newExternalDisplayCount == 0 {
            Log.powerEvents.log("Last external display disconnected")
            onLastExternalDisplayDisconnected()
        } else if previousExternalDisplayCount == 0 {
            Log.powerEvents.log("External display connected")
            onExternalDisplayConnected()
        }
    }

    /// Raw CoreGraphics callback that forwards completed reconfigurations to an observer instance.
    private static let reconfigurationCallback: CGDisplayReconfigurationCallBack = { _, flags, context in
        // Only the completion callback reports the final topology, so the begin phase is ignored.
        guard !flags.contains(.beginConfigurationFlag), let context else {
            return
        }

        let observer = Unmanaged<ExternalDisplayObserver>.fromOpaque(context).takeUnretainedValue()
        // CoreGraphics delivers reconfiguration callbacks on the main run loop.
        MainActor.assumeIsolated {
            observer.scheduleExternalDisplayCountRefresh()
        }
    }
}
