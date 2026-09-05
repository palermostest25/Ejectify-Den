//
//  DockDisconnectPolicyTests.swift
//  EjectifyTests
//
//  Created by Codex on 04/09/2026.
//

import Foundation
import Testing

struct DockDisconnectPolicyTests {

    /// Adapter used as the remembered dock in these tests.
    private let dock = PowerAdapterIdentity(adapterID: 4, familyCode: 12, manufacturer: "CalDigit", model: "TS4", watts: 96, serial: "DOCK-1")

    /// Apple charger that must never trigger an unmount.
    private let appleCharger = PowerAdapterIdentity(adapterID: 9, familyCode: 3, manufacturer: "Apple Inc.", model: "A2166", watts: 96, serial: "CHARGER-1")

    @Test func missingAdapterSnapshotIsIgnored() {
        let decision = DockDisconnectPolicy.decision(
            lostAdapter: nil,
            rememberedDocks: [dock],
            externalDisplayStillConnected: false
        )

        #expect(decision == .ignore(reason: "no adapter snapshot"))
    }

    @Test func lostAdapterIsIgnoredWithoutRememberedDocks() {
        let decision = DockDisconnectPolicy.decision(
            lostAdapter: dock,
            rememberedDocks: [],
            externalDisplayStillConnected: false
        )

        #expect(decision == .ignore(reason: "no remembered docks"))
    }

    @Test func chargerThatIsNotARememberedDockIsIgnored() {
        let decision = DockDisconnectPolicy.decision(
            lostAdapter: appleCharger,
            rememberedDocks: [dock],
            externalDisplayStillConnected: true
        )

        #expect(decision == .ignore(reason: "adapter not a remembered dock"))
    }

    @Test func rememberedDockLossUnmounts() {
        let decision = DockDisconnectPolicy.decision(
            lostAdapter: dock,
            rememberedDocks: [appleCharger, dock],
            externalDisplayStillConnected: false
        )

        #expect(decision == .unmount(reason: "remembered dock lost"))
    }

    @Test func connectedExternalDisplayDoesNotChangeTheDecision() {
        let withDisplay = DockDisconnectPolicy.decision(
            lostAdapter: dock,
            rememberedDocks: [dock],
            externalDisplayStillConnected: true
        )
        let withoutDisplay = DockDisconnectPolicy.decision(
            lostAdapter: dock,
            rememberedDocks: [dock],
            externalDisplayStillConnected: false
        )

        #expect(withDisplay == withoutDisplay)
    }

    @Test func anOpenLidBlocksTheTrigger() {
        let openLid = DockDisconnectPolicy.decision(
            lostAdapter: dock,
            rememberedDocks: [dock],
            externalDisplayStillConnected: false,
            isLidClosed: false,
            requiresClosedLid: true
        )
        #expect(openLid == .ignore(reason: "lid is open"))

        let closedLid = DockDisconnectPolicy.decision(
            lostAdapter: dock,
            rememberedDocks: [dock],
            externalDisplayStillConnected: false,
            isLidClosed: true,
            requiresClosedLid: true
        )
        #expect(closedLid == .unmount(reason: "remembered dock lost"))

        // A Mac that reports no clamshell state must not lose the trigger entirely.
        let unknownLid = DockDisconnectPolicy.decision(
            lostAdapter: dock,
            rememberedDocks: [dock],
            externalDisplayStillConnected: false,
            isLidClosed: nil,
            requiresClosedLid: true
        )
        #expect(unknownLid == .unmount(reason: "remembered dock lost"))
    }

    @Test func theLidRequirementGovernsEveryDisconnectTrigger() {
        #expect(DockDisconnectPolicy.allowsTrigger(isLidClosed: true, requiresClosedLid: true))
        #expect(DockDisconnectPolicy.allowsTrigger(isLidClosed: false, requiresClosedLid: true) == false)

        // Without the requirement the lid does not matter.
        #expect(DockDisconnectPolicy.allowsTrigger(isLidClosed: false, requiresClosedLid: false))

        // A Mac that reports no clamshell state keeps working.
        #expect(DockDisconnectPolicy.allowsTrigger(isLidClosed: nil, requiresClosedLid: true))
    }

    @Test func sleepAfterUnmountNeedsThePreferenceAndAFullySuccessfulBatch() {
        #expect(DockDisconnectPolicy.shouldSleepAfterUnmount(trigger: .dockDisconnected, sleepAfterDockDisconnect: true, requestedCount: 2, succeededCount: 2))
        #expect(DockDisconnectPolicy.shouldSleepAfterUnmount(trigger: .externalDisplayDisconnected, sleepAfterDockDisconnect: true, requestedCount: 1, succeededCount: 1))

        // The preference is off.
        #expect(DockDisconnectPolicy.shouldSleepAfterUnmount(trigger: .dockDisconnected, sleepAfterDockDisconnect: false, requestedCount: 1, succeededCount: 1) == false)

        // A volume stayed mounted, so the failure must stay visible instead.
        #expect(DockDisconnectPolicy.shouldSleepAfterUnmount(trigger: .dockDisconnected, sleepAfterDockDisconnect: true, requestedCount: 2, succeededCount: 1) == false)

        // An empty batch means the sleep trigger raced ahead and unmounted everything already.
        #expect(DockDisconnectPolicy.shouldSleepAfterUnmount(trigger: .dockDisconnected, sleepAfterDockDisconnect: true, requestedCount: 0, succeededCount: 0))
    }

    @Test func onlyTriggersThatLeaveTheMacAwakeCanRequestSleep() {
        // Sleeping after the sleep trigger would be circular, and the others are not power transitions.
        for trigger in [UnmountTrigger.systemStartsSleeping, .screensStartedSleeping, .screenIsLocked, .screensaverStarted] {
            #expect(DockDisconnectPolicy.shouldSleepAfterUnmount(trigger: trigger, sleepAfterDockDisconnect: true, requestedCount: 1, succeededCount: 1) == false)
        }
    }

    @Test func remountIsOnlyBlockedOnBatteryWithThePreferenceEnabled() {
        #expect(DockDisconnectPolicy.remountAllowed(isOnBattery: false, keepUnmountedOnBattery: false))
        #expect(DockDisconnectPolicy.remountAllowed(isOnBattery: false, keepUnmountedOnBattery: true))
        #expect(DockDisconnectPolicy.remountAllowed(isOnBattery: true, keepUnmountedOnBattery: false))
        #expect(DockDisconnectPolicy.remountAllowed(isOnBattery: true, keepUnmountedOnBattery: true) == false)
    }
}
