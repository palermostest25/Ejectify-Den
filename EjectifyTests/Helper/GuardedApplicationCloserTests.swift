//
//  GuardedApplicationCloserTests.swift
//  EjectifyTests
//
//  Created by Codex on 10/09/2026.
//

import Foundation
import Testing

struct GuardedApplicationCloserTests {

    @Test func closingNoApplicationsSucceedsWithoutTouchingAnything() async {
        // The preflight calls this whenever the guard list is empty, so it must be a cheap no-op.
        #expect(await GuardedApplicationCloser.closeApplications([]))
    }

    @Test func closingAnApplicationThatIsNotRunningSucceeds() async {
        // Nothing to close means nothing holding the volumes, which clears the disk operation.
        let notRunning = GuardedApplication(bundleIdentifier: "com.example.definitely-not-running", name: "Nothing")

        #expect(await GuardedApplicationCloser.closeApplications([notRunning]))
    }

    @Test func timeoutsLeaveRoomInsideTheSleepDelay() {
        // Sleep is only ever delayed ten seconds, and the unmounts themselves need part of that, so
        // one application's save plus quit has to fit in well under the cap.
        let perApplication = GuardedApplicationCloser.defaultSaveTimeout + GuardedApplicationCloser.defaultQuitTimeout

        #expect(perApplication < .seconds(10))
    }

    @Test func saveOutcomesReadAsStableLogText() {
        #expect(ApplicationSaveMenuController.Outcome.nothingToSave.logDescription == "nothing to save")
        #expect(ApplicationSaveMenuController.Outcome.saved.logDescription == "saved")
        #expect(ApplicationSaveMenuController.Outcome.didNotSettle.logDescription == "did not settle")
        #expect(ApplicationSaveMenuController.Outcome.unsupported.logDescription == "no save command")
        #expect(ApplicationSaveMenuController.Outcome.notPermitted.logDescription == "accessibility not permitted")
    }

    @Test func savingWithoutAccessibilityAccessReportsThatRatherThanGuessing() async {
        // The test runner is not a trusted Accessibility client, so this is the real unpermitted path.
        // Guarding on isPermitted keeps the test honest if it ever runs somewhere that is trusted.
        guard !ApplicationSaveMenuController.isPermitted else {
            return
        }

        let outcome = await ApplicationSaveMenuController.save(processIdentifier: getpid(), timeout: .milliseconds(100))

        #expect(outcome == .notPermitted)
    }
}
