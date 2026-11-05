//
//  DiffSummaryView.swift
//  DiffUI
//

import DiffCore
import SwiftUI

/// Compact, collapsible changed-files summary for a chat message.
///
/// The view owns no window and performs no Host loading. The host supplies a
/// `DiffChangeSummary`, optionally observes a selection binding, and decides
/// what "Review" means.
public struct DiffSummaryView: View {
    public let summary: DiffChangeSummary
    @Binding public var selectedFileID: String?
    public var onSelectFile: ((DiffSummaryFile) -> Void)?
    public var onReview: (() -> Void)?
    @State private var isExpanded: Bool

    public init(
        summary: DiffChangeSummary,
        selectedFileID: Binding<String?> = .constant(nil),
        initiallyExpanded: Bool = true,
        onSelectFile: ((DiffSummaryFile) -> Void)? = nil,
        onReview: (() -> Void)? = nil
    ) {
        self.summary = summary
        _selectedFileID = selectedFileID
        self.onSelectFile = onSelectFile
        self.onReview = onReview
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded, summary.hasFiles {
                Divider().padding(.horizontal, 10)
                VStack(spacing: 0) {
                    ForEach(summary.files) { file in
                        fileRow(file)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary.opacity(0.28))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.separator.opacity(0.55), lineWidth: 1)
        }
        .frame(maxWidth: 860, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Image(systemName: "plus.forwardslash.minus")
                        .foregroundStyle(.secondary)
                    Text(fileCountText)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Collapse changed files" : "Expand changed files")
            .accessibilityLabel("\(fileCountText), \(isExpanded ? "expanded" : "collapsed")")
            .accessibilityHint("Shows or hides the changed file list")

            DiffStatLabels(added: summary.added, deleted: summary.deleted)

            Spacer(minLength: 4)

            if summary.isTruncated {
                Text("Showing \(summary.files.count) of \(summary.total)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let onReview {
                Button("Open Full Review", action: onReview)
                    .buttonStyle(.borderless)
                    .accessibilityHint("Opens the full Diff review in the host application")
            }
        }
    }

    private func fileRow(_ file: DiffSummaryFile) -> some View {
        Button {
            selectedFileID = file.id
            onSelectFile?(file)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: icon(for: file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                Text(file.display)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.primary)
                if file.state != .modified {
                    Text(file.stateLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                DiffStatLabels(added: file.added, deleted: file.deleted)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selectedFileID == file.id ? Color.accentColor.opacity(0.14) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .help(file.path)
        .accessibilityLabel(
            "\(file.display), \(file.stateLabel), \(file.added) additions, \(file.deleted) deletions"
        )
        .accessibilityAddTraits(selectedFileID == file.id ? .isSelected : [])
    }

    private var fileCountText: String {
        summary.total == 1 ? "1 file changed" : "\(summary.total) files changed"
    }

    private func icon(for file: DiffSummaryFile) -> String {
        switch file.state {
        case .binary: "doc.badge.gearshape"
        case .oversized: "doc.badge.clock"
        case .unavailable: "doc.questionmark"
        case .added: "doc.badge.plus"
        case .deleted: "doc.badge.minus"
        case .empty, .modified, .coarse: "doc.text"
        }
    }
}
