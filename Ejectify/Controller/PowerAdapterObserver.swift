//
//  PowerAdapterObserver.swift
//  Ejectify
//
//  Created by Codex on 04/09/2026.
//

import Foundation
import IOKit.ps
import IOKit.pwr_mgt

/// Bridges IOKit power-source callbacks to main-actor handlers that report adapter losses and reconnections.
@MainActor
final class PowerAdapterObserver {

    /// Handler invoked once the Mac has been running on battery long enough to treat the adapter as lost.
    private let onAdapterLost: @MainActor (PowerAdapterIdentity) -> Void

    /// Handler invoked as soon as the Mac starts drawing external power again.
    private let onAdapterGained: @MainActor (PowerAdapterIdentity?) -> Void

    /// External power adapter currently reported by IOKit, or `nil` while running on battery.
    private(set) var currentAdapter: PowerAdapterIdentity?

    /// Whether IOKit currently reports battery as the providing power source.
    private(set) var isOnBattery = false

    /// Run loop source receiving power-source change callbacks.
    private var runLoopSource: CFRunLoopSource?

    /// Pending debounced adapter-loss notification.
    private var adapterLossTask: Task<Void, Never>?

    /// Pending re-poll of adapter details that were incomplete right after reconnecting.
    private var adapterDetailRefreshTask: Task<Void, Never>?

    /// Time the battery state must stay stable before an adapter loss is reported, so brief power renegotiation is ignored.
    private static let debounceInterval: Duration = .milliseconds(750)

    /// Delay between adapter detail re-polls while IOKit still reports an incomplete dictionary.
    private static let adapterDetailRetryInterval: Duration = .milliseconds(500)

    /// Number of times adapter details are re-polled before the reading is accepted as incomplete.
    private static let adapterDetailRetryLimit = 3

    /// Creates an observer that forwards adapter transitions to the supplied handlers.
    init(
        onAdapterLost: @escaping @MainActor (PowerAdapterIdentity) -> Void,
        onAdapterGained: @escaping @MainActor (PowerAdapterIdentity?) -> Void
    ) {
        self.onAdapterLost = onAdapterLost
        self.onAdapterGained = onAdapterGained
    }

    /// Registers for power-source notifications and seeds the current power state.
    @discardableResult
    func start() -> Bool {
        guard runLoopSource == nil else {
            return true
        }

        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let source = IOPSNotificationCreateRunLoopSource(Self.powerSourceCallback, context)?.takeRetainedValue() else {
            Log.powerEvents.error("Failed to register for power source notifications")
            return false
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, CFRunLoopMode.commonModes)
        runLoopSource = source

        // Seed state so the first callback compares against reality instead of a default.
        let snapshot = Self.snapshotPowerState()
        isOnBattery = snapshot.isOnBattery
        currentAdapter = snapshot.adapter
        Log.powerEvents.log("Power adapter monitoring enabled; onBattery=\(snapshot.isOnBattery)")
        return true
    }

    /// Stops power-source monitoring and cancels pending debounce and re-poll work.
    func stop() {
        cancelPendingWork()

        guard let runLoopSource else {
            return
        }

        CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, CFRunLoopMode.commonModes)
        CFRunLoopSourceInvalidate(runLoopSource)
        self.runLoopSource = nil
        Log.powerEvents.log("Power adapter monitoring disabled")
    }

    /// Returns the external power adapter attached right now, if any.
    nonisolated static func snapshotCurrentAdapter() -> PowerAdapterIdentity? {
        guard let details = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] else {
            return nil
        }

        return PowerAdapterIdentity(adapterDetails: details)
    }

    /// Returns whether IOKit currently reports battery as the providing power source.
    nonisolated static func snapshotIsOnBattery() -> Bool {
        snapshotPowerState().isOnBattery
    }

    /// Reads the providing power source and, while on external power, the attached adapter.
    private nonisolated static func snapshotPowerState() -> (isOnBattery: Bool, adapter: PowerAdapterIdentity?) {
        let isOnBattery = providingPowerSourceType() == kIOPMBatteryPowerKey
        return (isOnBattery, isOnBattery ? nil : snapshotCurrentAdapter())
    }

    /// Returns the power source type macOS reports as currently providing power.
    private nonisolated static func providingPowerSourceType() -> String? {
        guard let powerSourcesInfo = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return nil
        }

        guard let powerSourceType = IOPSGetProvidingPowerSourceType(powerSourcesInfo)?.takeUnretainedValue() else {
            return nil
        }

        return powerSourceType as String
    }

    /// Applies one power-source callback, emitting adapter transitions when the providing source changed.
    private func handlePowerSourceChange() {
        let snapshot = Self.snapshotPowerState()

        guard snapshot.isOnBattery != isOnBattery else {
            // Adapter details often arrive after the transition itself, so keep refining them while on external power.
            if !snapshot.isOnBattery {
                updateCurrentAdapter(with: snapshot.adapter)
            }
            return
        }

        let adapterBeforeChange = currentAdapter
        isOnBattery = snapshot.isOnBattery
        let adapterDescription = (snapshot.adapter ?? adapterBeforeChange)?.logDescription ?? "none"
        Log.powerEvents.info("Power source changed; onBattery=\(snapshot.isOnBattery); adapter=\(adapterDescription)")

        guard !snapshot.isOnBattery else {
            currentAdapter = nil
            scheduleAdapterLostNotification(adapter: adapterBeforeChange)
            return
        }

        // Reconnecting cancels a loss that has not been reported yet, and is never debounced itself.
        adapterLossTask?.cancel()
        adapterLossTask = nil
        updateCurrentAdapter(with: snapshot.adapter)
        scheduleAdapterDetailRefresh()
        onAdapterGained(currentAdapter)
    }

    /// Reports an adapter loss once the battery state has stayed stable for the debounce interval.
    private func scheduleAdapterLostNotification(adapter: PowerAdapterIdentity?) {
        adapterLossTask?.cancel()

        guard let adapter else {
            Log.powerEvents.info("Adapter loss not reported; reason=no adapter snapshot")
            adapterLossTask = nil
            return
        }

        adapterLossTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: PowerAdapterObserver.debounceInterval)
            } catch {
                return
            }

            guard let self, self.isOnBattery else {
                return
            }

            self.adapterLossTask = nil
            Log.powerEvents.log("Adapter lost after debounce; adapter=\(adapter.logDescription)")
            self.onAdapterLost(adapter)
        }
    }

    /// Re-polls adapter details until they identify the adapter, because IOKit reports them incrementally after reconnecting.
    private func scheduleAdapterDetailRefresh() {
        adapterDetailRefreshTask?.cancel()
        adapterDetailRefreshTask = nil

        guard !hasIdentifyingAdapterDetails else {
            return
        }

        adapterDetailRefreshTask = Task { @MainActor [weak self] in
            for attempt in 1...PowerAdapterObserver.adapterDetailRetryLimit {
                do {
                    try await Task.sleep(for: PowerAdapterObserver.adapterDetailRetryInterval)
                } catch {
                    return
                }

                guard let self, !self.isOnBattery else {
                    return
                }

                self.updateCurrentAdapter(with: PowerAdapterObserver.snapshotPowerState().adapter)

                guard !self.hasIdentifyingAdapterDetails else {
                    Log.powerEvents.info("Adapter details completed; attempt=\(attempt)")
                    self.adapterDetailRefreshTask = nil
                    return
                }

                if attempt == PowerAdapterObserver.adapterDetailRetryLimit {
                    Log.powerEvents.warning("Adapter details incomplete after retries; \(self.adapterFieldAvailabilityDescription)")
                    self.adapterDetailRefreshTask = nil
                }
            }
        }
    }

    /// Stores a newer adapter reading unless it would replace identifying fields with missing ones.
    private func updateCurrentAdapter(with adapter: PowerAdapterIdentity?) {
        guard let adapter else {
            return
        }

        guard !(hasIdentifyingAdapterDetails && adapter.adapterID == nil && adapter.serial == nil) else {
            return
        }

        currentAdapter = adapter
    }

    /// Whether the current adapter reading contains a field that can identify the adapter later.
    private var hasIdentifyingAdapterDetails: Bool {
        guard let currentAdapter else {
            return false
        }

        return currentAdapter.adapterID != nil || currentAdapter.serial != nil
    }

    /// Privacy-safe description of which adapter fields IOKit provided.
    private var adapterFieldAvailabilityDescription: String {
        guard let currentAdapter else {
            return "fields=none"
        }

        return "fields=adapterID:\(currentAdapter.adapterID != nil),familyCode:\(currentAdapter.familyCode != nil),manufacturer:\(currentAdapter.manufacturer != nil),model:\(currentAdapter.model != nil),serial:\(currentAdapter.serial != nil)"
    }

    /// Cancels pending debounce and re-poll tasks.
    private func cancelPendingWork() {
        adapterLossTask?.cancel()
        adapterLossTask = nil
        adapterDetailRefreshTask?.cancel()
        adapterDetailRefreshTask = nil
    }

    /// Raw IOKit callback that forwards power-source changes to an observer instance on the main run loop.
    private static let powerSourceCallback: IOPowerSourceCallbackType = { context in
        guard let context else {
            return
        }

        let observer = Unmanaged<PowerAdapterObserver>.fromOpaque(context).takeUnretainedValue()
        // The run loop source is attached to the main run loop, so this callback always arrives on the main thread.
        MainActor.assumeIsolated {
            observer.handlePowerSourceChange()
        }
    }
}
