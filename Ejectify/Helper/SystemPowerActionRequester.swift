//
//  SystemPowerActionRequester.swift
//  Ejectify
//
//  Created by Codex on 04/09/2026.
//

import Carbon
import Foundation

/// Asks macOS to sleep or restart by sending the matching Apple Event to the system process.
enum SystemPowerActionRequester {

    /// Power actions Ejectify can ask macOS to perform.
    enum Action {
        case sleep
        case restart

        /// Apple Event identifier for the action.
        var eventID: AEEventID {
            switch self {
            case .sleep: AEEventID(kAESleep)
            case .restart: AEEventID(kAERestart)
            }
        }

        /// Stable name used in logs.
        var logDescription: String {
            switch self {
            case .sleep: "sleep"
            case .restart: "restart"
            }
        }
    }

    /// Requests that macOS put the Mac to sleep.
    @discardableResult
    static func requestSleep() -> Bool {
        request(.sleep)
    }

    /// Requests that macOS restart the Mac.
    @discardableResult
    static func requestRestart() -> Bool {
        request(.restart)
    }

    /// Sends one power Apple Event to the system process and reports whether it was delivered.
    @discardableResult
    static func request(_ action: Action) -> Bool {
        var targetDescriptor = AEAddressDesc()
        let targetProcessSerialNumber = ProcessSerialNumber(highLongOfPSN: 0, lowLongOfPSN: UInt32(kSystemProcess))
        let targetCreateStatus = withUnsafePointer(to: targetProcessSerialNumber) { pointer in
            AECreateDesc(
                DescType(typeProcessSerialNumber),
                pointer,
                MemoryLayout<ProcessSerialNumber>.size,
                &targetDescriptor
            )
        }
        guard targetCreateStatus == noErr else {
            Log.powerEvents.error("System \(action.logDescription) target creation failed; status=\(targetCreateStatus)")
            return false
        }
        defer {
            AEDisposeDesc(&targetDescriptor)
        }

        var powerEvent = AppleEvent()
        let eventCreateStatus = AECreateAppleEvent(
            AEEventClass(kCoreEventClass),
            action.eventID,
            &targetDescriptor,
            AEReturnID(kAutoGenerateReturnID),
            AETransactionID(kAnyTransactionID),
            &powerEvent
        )
        guard eventCreateStatus == noErr else {
            Log.powerEvents.error("System \(action.logDescription) Apple Event creation failed; status=\(eventCreateStatus)")
            return false
        }
        defer {
            AEDisposeDesc(&powerEvent)
        }

        var eventReply = AppleEvent()
        defer {
            AEDisposeDesc(&eventReply)
        }

        let sendStatus = AESendMessage(
            &powerEvent,
            &eventReply,
            AESendMode(kAENoReply),
            kAEDefaultTimeout
        )
        guard sendStatus == noErr else {
            Log.powerEvents.error("System \(action.logDescription) Apple Event send failed; status=\(sendStatus)")
            return false
        }

        Log.powerEvents.log("System \(action.logDescription) Apple Event sent")
        return true
    }
}
