//
//  DiskOperationHUDView.swift
//  Ejectify
//
//  Created by Codex on 04/09/2026.
//

import AppKit
import SwiftUI

/// Progress panel shown under the status bar icon, styled after the app's report progress alert.
struct DiskOperationHUDView: View {

    /// Progress state driving the panel.
    @Bindable var progress: DiskOperationProgress

    /// Invoked when the user dismisses a panel that is reporting a failure.
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)

            Text(progress.title)
                .font(.system(size: 13, weight: .semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if !progress.subtitle.isEmpty {
                Text(progress.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ProgressView(value: Double(progress.completedCount), total: Double(max(progress.totalCount, 1)))
                .progressViewStyle(.linear)
                .tint(progress.hasFailure ? .orange : .accentColor)

            if progress.isFinished, progress.hasFailure {
                failureDetails

                Button(String(localized: "OK"), action: onDismiss)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.small)
            }
        }
        .padding(18)
        .frame(width: 260)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .shadow(radius: 16, y: 6)
        .padding(10)
        .animation(.easeInOut(duration: 0.18), value: progress.completedCount)
    }

    /// Per-volume reasons, shown only when something could not be handled.
    private var failureDetails: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(progress.failedRows) { row in
                if case .failed(let reason) = row.state, let reason {
                    Text(reason)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
