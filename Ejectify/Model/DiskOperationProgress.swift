//
//  DiskOperationProgress.swift
//  Ejectify
//
//  Created by Codex on 04/09/2026.
//

import Foundation

/// Tracks one batch of disk operations so the status bar HUD can report progress and failures.
@MainActor
@Observable
final class DiskOperationProgress {

    /// Shared progress state observed by the HUD.
    static let shared = DiskOperationProgress()

    /// The kind of batch being reported.
    enum Kind: Sendable {
        case unmounting
        case mounting
        case ejecting

        /// Title shown while the batch runs.
        var runningTitle: String {
            switch self {
            case .unmounting: String(localized: "Unmounting disks…")
            case .mounting: String(localized: "Remounting disks…")
            case .ejecting: String(localized: "Ejecting disks…")
            }
        }

        /// Title shown once every volume in the batch has finished successfully.
        var succeededTitle: String {
            switch self {
            case .unmounting: String(localized: "Disks unmounted")
            case .mounting: String(localized: "Disks remounted")
            case .ejecting: String(localized: "Disks ejected")
            }
        }

        /// Title shown when at least one volume failed.
        var failedTitle: String {
            switch self {
            case .unmounting: String(localized: "Could not unmount every disk")
            case .mounting: String(localized: "Could not remount every disk")
            case .ejecting: String(localized: "Could not eject every disk")
            }
        }
    }

    /// Outcome of one volume within the batch.
    enum RowState: Equatable, Sendable {
        case running
        case succeeded
        case failed(reason: String?)
    }

    /// One volume's row in the HUD.
    struct Row: Identifiable, Equatable, Sendable {

        /// Stable volume identifier used to update the row when its operation finishes.
        let id: String

        /// Volume name shown to the user.
        let name: String

        /// Current outcome for this volume.
        var state: RowState
    }

    /// The batch currently being reported.
    private(set) var kind: Kind = .unmounting

    /// Rows for the batch, in the order the volumes were requested.
    private(set) var rows: [Row] = []

    /// Whether a batch is currently being reported at all.
    private(set) var isActive = false

    /// Whether every row has reached a final state.
    var isFinished: Bool {
        !rows.isEmpty && rows.allSatisfy { $0.state != .running }
    }

    /// Whether any volume in the batch failed.
    var hasFailure: Bool {
        rows.contains { row in
            if case .failed = row.state {
                return true
            }
            return false
        }
    }

    /// Number of volumes in the batch that have finished.
    var completedCount: Int {
        rows.filter { $0.state != .running }.count
    }

    /// Number of volumes in the batch.
    var totalCount: Int {
        rows.count
    }

    /// Volumes that could not be handled, with the reason where one is known.
    var failedRows: [Row] {
        rows.filter { row in
            if case .failed = row.state {
                return true
            }
            return false
        }
    }

    /// Secondary line naming the volumes being handled, mirroring an alert's informative text.
    var subtitle: String {
        guard isFinished, hasFailure else {
            return rows.map(\.name).joined(separator: ", ")
        }

        return failedRows.map(\.name).joined(separator: ", ")
    }

    /// Title matching the batch's current state.
    var title: String {
        guard isFinished else {
            return kind.runningTitle
        }

        return hasFailure ? kind.failedTitle : kind.succeededTitle
    }

    /// Starts reporting a new batch, replacing anything already on screen.
    func begin(kind: Kind, volumes: [(id: String, name: String)]) {
        self.kind = kind
        rows = volumes.map { Row(id: $0.id, name: $0.name, state: .running) }
        isActive = !rows.isEmpty
    }

    /// Records the outcome for one volume in the batch.
    func finish(volumeID: String, state: RowState) {
        guard let index = rows.firstIndex(where: { $0.id == volumeID }) else {
            return
        }

        rows[index].state = state
    }

    /// Clears the batch once the HUD has been dismissed.
    func clear() {
        rows = []
        isActive = false
    }
}
