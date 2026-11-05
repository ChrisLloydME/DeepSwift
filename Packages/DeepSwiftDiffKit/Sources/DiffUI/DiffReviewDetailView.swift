//
//  DiffReviewDetailView.swift
//  DiffUI
//

import DiffCore
import SwiftUI

/// The single-file detail surface used by both `DiffReviewView` and hosts that
/// provide their own navigation container.
///
/// File metadata and hunk navigation live here. The presentation mode is owned
/// by the host so it can reside in a native window toolbar.
public struct DiffReviewDetailView: View {
    public let file: DiffFile
    public let configuration: DiffReviewConfiguration
    @Binding public var mode: DiffPresentationMode

    @State private var selectedHunk = 0

    public init(
        file: DiffFile,
        configuration: DiffReviewConfiguration = .init(),
        mode: Binding<DiffPresentationMode>
    ) {
        self.file = file
        self.configuration = configuration
        _mode = mode
    }

    public var body: some View {
        VStack(spacing: 0) {
            DiffFileHeaderView(file: file)
            Divider()
            if file.hunks.isEmpty || file.isBinary || file.isOversized || file.isUnavailable {
                DiffUnavailableState(file: file)
            } else {
                hunkToolbar
                Divider()
                if mode == .unified {
                    UnifiedDiffView(
                        file: file,
                        selectedHunk: selectedHunk,
                        configuration: configuration.diff
                    )
                } else {
                    SideBySideDiffView(
                        file: file,
                        selectedHunk: selectedHunk,
                        configuration: configuration.diff
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var hunkToolbar: some View {
        HStack(spacing: 8) {
            Button {
                selectedHunk = max(0, selectedHunk - 1)
            } label: {
                Label("Previous Hunk", systemImage: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(selectedHunk <= 0)
            .help("Previous hunk")
            .accessibilityHint("Moves to the previous changed region")

            Button {
                selectedHunk = min(file.hunks.count - 1, selectedHunk + 1)
            } label: {
                Label("Next Hunk", systemImage: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(selectedHunk >= file.hunks.count - 1)
            .help("Next hunk")
            .accessibilityHint("Moves to the next changed region")

            Text("Hunk \(selectedHunk + 1) of \(file.hunks.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("Hunk \(selectedHunk + 1) of \(file.hunks.count)")

            Spacer()
            if file.isCoarse {
                Text("Coarse comparison")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help("The Host treated this file as a whole-file replacement.")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.18))
    }
}
