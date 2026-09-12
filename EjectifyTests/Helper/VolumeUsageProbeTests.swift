//
//  VolumeUsageProbeTests.swift
//  EjectifyTests
//
//  Created by Codex on 12/09/2026.
//

import Foundation
import Testing

struct VolumeUsageProbeTests {

    @Test func parsingPairsEachProcessIdentifierWithItsCommand() {
        // lsof field output: a process record, then that process's files, then the next process.
        let output = """
        p501
        czsh
        n/Volumes/Music
        p712
        crekordbox
        n/Volumes/Music/library.db
        """

        let processes = VolumeUsageProbe.parse(output)

        #expect(processes.map(\.processIdentifier) == [501, 712])
        #expect(processes.map(\.name) == ["zsh", "rekordbox"])
    }

    @Test func aCommandCarriesForwardTheMostRecentIdentifier() {
        // Identity is stated once and applies until the next p line, so a stray ordering must not
        // attach a command to the wrong process.
        let processes = VolumeUsageProbe.parse("p1\ncfirst\np2\ncsecond\n")

        #expect(processes == [
            VolumeUsageProbe.BlockingProcess(processIdentifier: 1, name: "first"),
            VolumeUsageProbe.BlockingProcess(processIdentifier: 2, name: "second")
        ])
    }

    @Test func outputWithoutAProcessIdentifierYieldsNothing() {
        #expect(VolumeUsageProbe.parse("corphan\nn/Volumes/Music").isEmpty)
        #expect(VolumeUsageProbe.parse("").isEmpty)
    }

    @Test func unparsableIdentifiersAreIgnoredRatherThanGuessed() {
        #expect(VolumeUsageProbe.parse("pnot-a-number\ncshell").isEmpty)
    }

    @Test func usageWithNothingFoundIsEmpty() {
        let usage = VolumeUsage(applications: [], otherProcessNames: [])

        #expect(usage.isEmpty)
        #expect(usage.displayNames.isEmpty)
    }

    @Test func displayNamesPutActionableApplicationsFirst() {
        // The user can be offered a way to quit an application; a stray daemon can only be named.
        let usage = VolumeUsage(
            applications: [GuardedApplication(bundleIdentifier: "com.apple.Terminal", name: "Terminal")],
            otherProcessNames: ["mds_stores"]
        )

        #expect(usage.displayNames == ["Terminal", "mds_stores"])
        #expect(usage.isEmpty == false)
    }

    @Test func probingAVolumeThatDoesNotExistFindsNothing() {
        // lsof is really run here, so this also proves the probe returns rather than hanging.
        let usage = VolumeUsageProbe.usage(ofVolumeAt: URL(fileURLWithPath: "/Volumes/\(UUID().uuidString)"))

        #expect(usage.isEmpty)
    }
}
