//
//  GuardedApplicationPolicy.swift
//  Ejectify
//
//  Created by Codex on 08/09/2026.
//

import Foundation

/// Decides whether a guarded application is running and should therefore hold a disk operation back.
enum GuardedApplicationPolicy {

    /// Guarded applications that are running right now, in the order the user added them.
    ///
    /// An empty result means nothing is holding the volumes, so the caller may proceed.
    static func blockingApplications(
        guardedApplications: [GuardedApplication],
        runningApplications: [RunningApplication]
    ) -> [GuardedApplication] {
        guard !guardedApplications.isEmpty, !runningApplications.isEmpty else {
            return []
        }

        return guardedApplications.filter { $0.isRunning(among: runningApplications) }
    }

    /// Joins two lists of guarded applications, keeping the first occurrence of each.
    static func merged(_ applications: [GuardedApplication], with others: [GuardedApplication]) -> [GuardedApplication] {
        var seenIdentifiers = Set(applications.map(\.id))

        return applications + others.filter { seenIdentifiers.insert($0.id).inserted }
    }

    /// Applications whose own bundle lives on one of these volumes.
    ///
    /// Unmounting the disk an application is running from pulls its executable and resources out
    /// from under it, which is how a set gets lost without any file of the user's being written.
    /// These are guarded whether or not the user thought to tick them.
    static func applicationsRunning(
        fromVolumesAt volumeURLs: [URL],
        among runningApplications: [RunningApplication]
    ) -> [GuardedApplication] {
        guard !volumeURLs.isEmpty else {
            return []
        }

        let volumePaths = volumeURLs.map(\.standardizedFileURL.pathComponents)

        return runningApplications.compactMap { runningApplication in
            guard let bundleURL = runningApplication.bundleURL,
                  volumePaths.contains(where: { isPath(bundleURL.standardizedFileURL.pathComponents, under: $0) }) else {
                return nil
            }

            return GuardedApplication(bundleIdentifier: runningApplication.bundleIdentifier, name: runningApplication.name)
        }
    }

    /// Whether one path sits inside another, compared component by component.
    ///
    /// Plain string prefixes would put "/Volumes/Music" inside "/Volumes/Music Backup", which would
    /// guard applications on a disk that is not being touched.
    private static func isPath(_ path: [String], under directory: [String]) -> Bool {
        guard path.count > directory.count else {
            return false
        }

        return Array(path.prefix(directory.count)) == directory
    }

    /// The rows a picker should offer: everything already guarded, plus the apps running now.
    ///
    /// A guarded app that has since quit has to stay listed, or there would be no way to untick it.
    /// `excludingBundleIdentifier` drops Ejectify itself, which is always running and would only
    /// invite a setting that silently disables every automatic unmount.
    static func selectableApplications(
        guardedApplications: [GuardedApplication],
        runningApplications: [RunningApplication],
        excludingBundleIdentifier: String? = nil
    ) -> [GuardedApplication] {
        var seenIdentifiers = Set(guardedApplications.map(\.id))
        var applications = guardedApplications

        for runningApplication in runningApplications where runningApplication.isUserFacing {
            if let excludingBundleIdentifier,
               let bundleIdentifier = runningApplication.bundleIdentifier,
               bundleIdentifier.caseInsensitiveCompare(excludingBundleIdentifier) == .orderedSame {
                continue
            }

            let application = GuardedApplication(bundleIdentifier: runningApplication.bundleIdentifier, name: runningApplication.name)
            guard seenIdentifiers.insert(application.id).inserted else {
                continue
            }

            applications.append(application)
        }

        return applications.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Names of the blocking applications, joined for display in an alert or the menu.
    static func description(of blockingApplications: [GuardedApplication]) -> String {
        blockingApplications.map(\.name).joined(separator: ", ")
    }

    /// Names of the blocking applications, joined for a log line that must not carry user content.
    ///
    /// Bundle identifiers are program identity rather than anything the user wrote, so they are safe
    /// to log; a name the user could have renamed is reduced to a count instead.
    static func logDescription(of blockingApplications: [GuardedApplication]) -> String {
        guard !blockingApplications.isEmpty else {
            return "none"
        }

        let identifiers = blockingApplications.compactMap(\.bundleIdentifier)
        guard !identifiers.isEmpty else {
            return "count=\(blockingApplications.count)"
        }

        return identifiers.joined(separator: ",")
    }
}
