//
//  GuardedApplicationCloser.swift
//  Ejectify
//
//  Created by Codex on 10/09/2026.
//

import AppKit

/// Asks guarded applications to save and quit so their volumes can be unmounted safely.
///
/// Saving is best effort, because no API can compel another process to write its documents. The
/// gate is therefore the quit: an application that has actually exited is holding nothing open,
/// whatever happened while it was asked to save. Nothing is ever force-terminated, so every
/// failure leaves the application running and the volumes mounted, which is the safe direction.
@MainActor
enum GuardedApplicationCloser {

    /// How long one application gets to settle its Save item before being asked to quit.
    nonisolated static let defaultSaveTimeout = Duration.seconds(3)

    /// How long one application gets to exit after being asked to quit.
    nonisolated static let defaultQuitTimeout = Duration.seconds(4)

    /// How often a quitting application is re-checked.
    nonisolated private static let pollInterval = Duration.milliseconds(150)

    /// Asks every running instance of these applications to save and quit.
    ///
    /// Returns whether all of them exited, which is the only result that clears a disk operation.
    static func closeApplications(
        _ applications: [GuardedApplication],
        saveTimeout: Duration = defaultSaveTimeout,
        quitTimeout: Duration = defaultQuitTimeout
    ) async -> Bool {
        guard !applications.isEmpty else {
            return true
        }

        if !ApplicationSaveMenuController.isPermitted {
            Log.volumeOperations.warning("Accessibility access missing; guarded applications can only be asked to quit, not to save first")
        }

        var didEveryApplicationClose = true
        for processIdentifier in processIdentifiers(of: applications) {
            let didClose = await closeApplication(
                processIdentifier: processIdentifier,
                saveTimeout: saveTimeout,
                quitTimeout: quitTimeout
            )
            didEveryApplicationClose = didEveryApplicationClose && didClose
        }

        return didEveryApplicationClose
    }

    /// Process identifiers of every running instance of these guarded applications.
    ///
    /// Identifiers rather than the applications themselves, because one application can be running
    /// several times and each copy holds its own documents open.
    private static func processIdentifiers(of applications: [GuardedApplication]) -> [pid_t] {
        RunningApplicationProbe.runningApplicationsWithProcessIdentifiers().compactMap { entry in
            guard applications.contains(where: { $0.matches(entry.application) }) else {
                return nil
            }

            return entry.processIdentifier
        }
    }

    /// Asks one application to save and then quit, and reports whether it exited.
    private static func closeApplication(
        processIdentifier: pid_t,
        saveTimeout: Duration,
        quitTimeout: Duration
    ) async -> Bool {
        let saveOutcome = await ApplicationSaveMenuController.save(processIdentifier: processIdentifier, timeout: saveTimeout)
        Log.volumeOperations.log("Guarded application asked to save; pid=\(processIdentifier); outcome=\(saveOutcome.logDescription)")

        guard isRunning(processIdentifier: processIdentifier) else {
            // It exited while saving, which is exactly what was being asked for.
            return true
        }

        guard NSRunningApplication(processIdentifier: processIdentifier)?.terminate() == true else {
            Log.volumeOperations.warning("Guarded application refused the quit request; pid=\(processIdentifier)")
            return false
        }

        let didExit = await waitUntilTerminated(processIdentifier: processIdentifier, timeout: quitTimeout)
        if didExit {
            Log.volumeOperations.log("Guarded application quit; pid=\(processIdentifier)")
        } else {
            // Almost always an unanswered save dialog. Killing it would defeat the entire point.
            Log.volumeOperations.warning("Guarded application did not quit in time; pid=\(processIdentifier)")
        }

        return didExit
    }

    /// Waits for an application to exit, returning false if it is still running at the deadline.
    private static func waitUntilTerminated(processIdentifier: pid_t, timeout: Duration) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)

        while ContinuousClock.now < deadline {
            do {
                try await Task.sleep(for: pollInterval)
            } catch {
                return !isRunning(processIdentifier: processIdentifier)
            }

            if !isRunning(processIdentifier: processIdentifier) {
                return true
            }
        }

        return !isRunning(processIdentifier: processIdentifier)
    }

    /// Whether a process is still a running application, treating an unknown identifier as gone.
    private static func isRunning(processIdentifier: pid_t) -> Bool {
        guard let application = NSRunningApplication(processIdentifier: processIdentifier) else {
            return false
        }

        return !application.isTerminated
    }
}

extension ApplicationSaveMenuController.Outcome {

    /// Stable wording for logs, so a save result reads without decoding an enum case name.
    var logDescription: String {
        switch self {
        case .nothingToSave: "nothing to save"
        case .saved: "saved"
        case .didNotSettle: "did not settle"
        case .unsupported: "no save command"
        case .notPermitted: "accessibility not permitted"
        }
    }
}
