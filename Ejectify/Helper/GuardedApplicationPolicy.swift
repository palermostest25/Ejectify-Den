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
