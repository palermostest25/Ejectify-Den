//
//  DiskOperationHUDView.swift
//  Ejectify
//
//  Created by Codex on 04/09/2026.
//

import SwiftUI

/// Compact progress panel shown under the status bar icon while volumes are handled.
struct DiskOperationHUDView: View {

    /// Progress state driving the panel.
    @Bindable var progress: DiskOperationProgress

    /// Invoked when the user dismisses a panel that is reporting a failure.
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if !progress.rows.isEmpty {
                Divider()
                    .opacity(0.5)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(progress.rows) { row in
                        DiskOperationHUDRow(row: row)
                    }
                }
            }

            if progress.isFinished, progress.hasFailure {
                Button(String(localized: "OK"), action: onDismiss)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(14)
        .frame(width: 260)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .shadow(radius: 12, y: 4)
        .padding(8)
        .animation(.easeInOut(duration: 0.18), value: progress.rows)
    }

    /// Title row with the icon that reflects the batch outcome.
    private var header: some View {
        HStack(spacing: 8) {
            headerIcon
                .frame(width: 16, height: 16)

            Text(progress.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Spinner while running, then a summary symbol.
    @ViewBuilder
    private var headerIcon: some View {
        if progress.isFinished {
            Image(systemName: progress.hasFailure ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(progress.hasFailure ? Color.orange : Color.green)
        } else {
            ProgressView()
                .controlSize(.small)
        }
    }
}

/// One volume row inside the progress panel.
private struct DiskOperationHUDRow: View {

    /// Row to render.
    let row: DiskOperationProgress.Row

    var body: some View {
        HStack(spacing: 8) {
            stateIcon
                .frame(width: 14, height: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(row.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if case .failed(let reason) = row.state, let reason {
                    Text(reason)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
    }

    /// Per-volume outcome symbol.
    @ViewBuilder
    private var stateIcon: some View {
        switch row.state {
        case .running:
            ProgressView()
                .controlSize(.mini)
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }
}
