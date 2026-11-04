//
//  DiffStateViews.swift
//  DiffUI
//

import DiffCore
import SwiftUI

struct DiffUnavailableState: View {
    let file: DiffFile

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var title: String {
        switch file.state {
        case .binary: "Binary File"
        case .oversized: "File Too Large"
        case .unavailable: "Comparison Unavailable"
        case .empty: "Empty File"
        case .added: "New File"
        case .deleted: "Deleted File"
        case .coarse: "Coarse Comparison"
        case .modified: "No Comparison"
        }
    }

    private var systemImage: String {
        switch file.state {
        case .binary: "doc.badge.gearshape"
        case .oversized: "doc.badge.clock"
        case .unavailable: "doc.questionmark"
        case .empty: "doc"
        case .added: "doc.badge.plus"
        case .deleted: "doc.badge.minus"
        case .coarse: "doc.text.magnifyingglass"
        case .modified: "doc.text.magnifyingglass"
        }
    }

    private var message: String {
        switch file.state {
        case .binary:
            "This file has no textual comparison. Its original and updated content are not shown as lines."
        case .oversized:
            "The DSH Host did not retain a line comparison for this file because it is too large."
        case .unavailable:
            "The comparison is no longer available. DeepSwiftDiffKit does not recreate it from the current workspace."
        case .empty:
            "This file has no lines to compare."
        case .added:
            "This new file has no lines."
        case .deleted:
            "This deleted file had no lines."
        case .coarse:
            "The Host provided a whole-file replacement rather than a fine-grained line comparison."
        case .modified:
            "No textual hunks were provided for this file."
        }
    }
}

struct CoarseComparisonBanner: View {
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "exclamationmark.triangle")
            Text("Coarse comparison — the Host treated this as a whole-file replacement.")
                .font(.caption)
            Spacer()
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.orange.opacity(0.08))
        .accessibilityElement(children: .combine)
    }
}

struct DiffFileHeaderView: View {
    let file: DiffFile

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.display)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(file.path)
                HStack(spacing: 7) {
                    Text(file.stateLabel)
                    if file.before == false { Text("new file") }
                    if file.after == false { Text("deleted file") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            DiffStatLabels(added: file.added, deleted: file.deleted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(file.display), \(file.stateLabel), \(file.added) additions, \(file.deleted) deletions")
    }

    private var icon: String {
        switch file.state {
        case .binary: "doc.badge.gearshape"
        case .oversized: "doc.badge.clock"
        case .unavailable: "doc.questionmark"
        case .added: "doc.badge.plus"
        case .deleted: "doc.badge.minus"
        case .coarse: "doc.text.magnifyingglass"
        case .empty, .modified: "doc.text"
        }
    }
}

struct DiffStatLabels: View {
    let added: Int
    let deleted: Int

    var body: some View {
        HStack(spacing: 6) {
            if added > 0 {
                Text("+\(added)")
                    .foregroundStyle(.green)
                    .accessibilityLabel("\(added) additions")
            }
            if deleted > 0 {
                Text("−\(deleted)")
                    .foregroundStyle(.red)
                    .accessibilityLabel("\(deleted) deletions")
            }
        }
        .font(.caption.monospacedDigit())
    }
}

extension DiffFile {
    var stateLabel: String {
        switch state {
        case .modified: "Modified"
        case .added: "Added"
        case .deleted: "Deleted"
        case .binary: "Binary"
        case .oversized: "Too large"
        case .coarse: "Coarse comparison"
        case .empty: "Empty"
        case .unavailable: "Unavailable"
        }
    }
}
