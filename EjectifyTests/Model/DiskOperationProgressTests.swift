//
//  DiskOperationProgressTests.swift
//  EjectifyTests
//
//  Created by Codex on 12/09/2026.
//

import Foundation
import Testing

@MainActor
struct DiskOperationProgressTests {

    /// Builds a progress model holding one batch, so tests never touch the shared instance.
    private func makeProgress(kind: DiskOperationProgress.Kind = .mounting, volumeIDs: [String]) -> DiskOperationProgress {
        let progress = DiskOperationProgress()
        progress.begin(kind: kind, volumes: volumeIDs.map { (id: $0, name: "Volume \($0)") })
        return progress
    }

    @Test func aBatchIsUnfinishedWhileAnyRowIsStillRunning() {
        let progress = makeProgress(volumeIDs: ["a", "b"])

        progress.finish(volumeID: "a", state: .succeeded)

        #expect(progress.isFinished == false)
    }

    @Test func droppingTheLastRunningRowFinishesTheBatch() {
        // The panel stays on screen until every row is accounted for, so a remount that gave up
        // without succeeding or failing has to release its row or the panel never goes away.
        let progress = makeProgress(volumeIDs: ["a", "b"])
        progress.finish(volumeID: "a", state: .succeeded)

        #expect(progress.remove(volumeID: "b"))
        #expect(progress.isFinished)
        #expect(progress.hasFailure == false)
        #expect(progress.totalCount == 1)
    }

    @Test func droppingEveryRowLeavesNothingToReport() {
        let progress = makeProgress(volumeIDs: ["a"])

        #expect(progress.remove(volumeID: "a"))
        #expect(progress.rows.isEmpty)
        // An empty batch is not "finished", which is why the controller dismisses on an empty result.
        #expect(progress.isFinished == false)
    }

    @Test func aRowThatAlreadyReportedIsNeverDropped() {
        let progress = makeProgress(volumeIDs: ["a", "b"])
        progress.finish(volumeID: "a", state: .succeeded)
        progress.finish(volumeID: "b", state: .failed(reason: "busy"))

        #expect(progress.remove(volumeID: "a") == false)
        #expect(progress.remove(volumeID: "b") == false)
        #expect(progress.totalCount == 2)
        #expect(progress.hasFailure)
    }

    @Test func droppingAnUnknownVolumeChangesNothing() {
        let progress = makeProgress(volumeIDs: ["a"])

        #expect(progress.remove(volumeID: "elsewhere") == false)
        #expect(progress.totalCount == 1)
    }

    @Test func aDroppedRowDoesNotCountAsAFailure() {
        // Giving up on a deferred remount is not a failure, so the panel must not go red over it.
        let progress = makeProgress(volumeIDs: ["a", "b"])
        progress.finish(volumeID: "a", state: .succeeded)
        progress.remove(volumeID: "b")

        #expect(progress.hasFailure == false)
        #expect(progress.title == DiskOperationProgress.Kind.mounting.succeededTitle)
    }

    @Test func subtitleNamesOnlyTheFailuresOnceFinished() {
        let progress = makeProgress(volumeIDs: ["a", "b"])
        progress.finish(volumeID: "a", state: .succeeded)
        progress.finish(volumeID: "b", state: .failed(reason: "busy"))

        #expect(progress.subtitle == "Volume b")
    }
}
