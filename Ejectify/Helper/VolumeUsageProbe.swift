//
//  VolumeUsageProbe.swift
//  Ejectify
//
//  Created by Codex on 12/09/2026.
//

import AppKit
import Darwin

/// What is keeping a volume busy, split into things that can be quit and things that can only be named.
struct VolumeUsage: Sendable, Equatable {

    /// Applications holding the volume, which the user can be offered a way to quit.
    let applications: [GuardedApplication]

    /// Names of processes that belong to no application, such as a daemon or a detached shell.
    let otherProcessNames: [String]

    /// Whether nothing was found holding the volume.
    var isEmpty: Bool {
        applications.isEmpty && otherProcessNames.isEmpty
    }

    /// Every blocker named for display, applications first because those are the actionable ones.
    var displayNames: [String] {
        applications.map(\.name) + otherProcessNames
    }
}

/// Finds what is holding a volume open after an unmount is refused as busy.
///
/// Disk Arbitration reports only that the volume is in use, never by whom, so "the disk is in use"
/// is all a failed unmount can say on its own. `lsof` answers the rest, and unlike walking open
/// files by hand it also reports a working directory, which is how a shell sitting in a folder keeps
/// a disk mounted without holding a single file open.
enum VolumeUsageProbe {

    /// Path to the system tool, which is where lsof lives on every supported macOS.
    private static let toolURL = URL(fileURLWithPath: "/usr/sbin/lsof")

    /// How long the probe may take before its answer stops being worth waiting for.
    ///
    /// This runs inside the sleep delay an unmount is already spending, so it cannot hang about.
    private static let timeout: TimeInterval = 2

    /// How far up the process tree to look for the application a process belongs to.
    ///
    /// A shell is a child of Terminal, and a shell's child is a grandchild, so a few levels covers
    /// the realistic cases without walking all the way to launchd.
    private static let maximumParentDepth = 4

    /// Returns what is holding the volume at this mount point, or an empty result when nothing is.
    static func usage(ofVolumeAt volumeURL: URL) -> VolumeUsage {
        let ownProcessIdentifier = ProcessInfo.processInfo.processIdentifier

        var applications: [GuardedApplication] = []
        var otherNames: [String] = []
        var seenApplicationIdentifiers = Set<String>()
        var seenOtherNames = Set<String>()

        for process in processes(usingVolumeAt: volumeURL) where process.processIdentifier != ownProcessIdentifier {
            guard let application = owningApplication(of: process.processIdentifier) else {
                if seenOtherNames.insert(process.name).inserted {
                    otherNames.append(process.name)
                }
                continue
            }

            if seenApplicationIdentifiers.insert(application.id).inserted {
                applications.append(application)
            }
        }

        return VolumeUsage(applications: applications, otherProcessNames: otherNames)
    }

    /// One process reported as using the volume.
    struct BlockingProcess: Equatable {
        let processIdentifier: pid_t
        let name: String
    }

    /// Asks lsof which processes hold the volume, returning nothing if it cannot be asked.
    private static func processes(usingVolumeAt volumeURL: URL) -> [BlockingProcess] {
        // A mount point argument makes lsof report every open file on that filesystem, which is far
        // cheaper than asking it to walk the directory tree.
        guard let output = runTool(arguments: ["-F", "pcn", "-w", "-n", "-P", "--", volumeURL.path]) else {
            return []
        }

        return parse(output)
    }

    /// Parses lsof's field output, where each line is a type character followed by its value.
    ///
    /// Records arrive as a process identifier, then a command name, then that process's files, so
    /// the current identity is carried forward until the next `p` line replaces it.
    static func parse(_ output: String) -> [BlockingProcess] {
        var processes: [BlockingProcess] = []
        var currentIdentifier: pid_t?

        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let value = String(line.dropFirst())

            switch line.first {
            case "p":
                currentIdentifier = pid_t(value)
            case "c":
                guard let identifier = currentIdentifier, !value.isEmpty else {
                    continue
                }

                processes.append(BlockingProcess(processIdentifier: identifier, name: value))
            default:
                continue
            }
        }

        return processes
    }

    /// Runs lsof and returns its output, giving up rather than waiting on a tool that will not finish.
    private static func runTool(arguments: [String]) -> String? {
        guard FileManager.default.isExecutableFile(atPath: toolURL.path) else {
            Log.volumeOperations.warning("Cannot identify what is using the volume; reason=lsof unavailable")
            return nil
        }

        let process = Process()
        process.executableURL = toolURL
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            Log.volumeOperations.warning("Cannot identify what is using the volume; reason=lsof could not start")
            return nil
        }

        // Signal the child by identifier rather than capturing the process itself, and schedule it
        // before reading: reading to end of file blocks until the child closes its output, so a
        // wedged lsof would otherwise outlast any timeout checked afterwards. The identifier cannot
        // be reused in the meantime, because the child is not reaped until waitUntilExit below.
        let processIdentifier = process.processIdentifier
        let watchdog = DispatchWorkItem {
            kill(processIdentifier, SIGTERM)
            Log.volumeOperations.warning("Gave up identifying what is using the volume; reason=lsof timed out")
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout, execute: watchdog)

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()

        return String(data: data, encoding: .utf8)
    }

    /// Finds the application a process belongs to, walking up to its parents when it is not one itself.
    ///
    /// A shell holding a working directory is a child of the terminal that launched it, and quitting
    /// the terminal is the action a user can actually take.
    private static func owningApplication(of processIdentifier: pid_t) -> GuardedApplication? {
        var identifier = processIdentifier

        for _ in 0...maximumParentDepth {
            if let application = NSRunningApplication(processIdentifier: identifier),
               !application.isTerminated,
               let name = application.localizedName ?? application.bundleURL?.deletingPathExtension().lastPathComponent {
                return GuardedApplication(bundleIdentifier: application.bundleIdentifier, name: name)
            }

            guard let parentIdentifier = parentProcessIdentifier(of: identifier), parentIdentifier > 1 else {
                return nil
            }

            identifier = parentIdentifier
        }

        return nil
    }

    /// Reads a process's parent identifier, returning nil when the process is gone or unreadable.
    private static func parentProcessIdentifier(of processIdentifier: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let readSize = proc_pidinfo(processIdentifier, PROC_PIDTBSDINFO, 0, &info, size)

        guard readSize == size else {
            return nil
        }

        return pid_t(truncatingIfNeeded: info.pbi_ppid)
    }
}
