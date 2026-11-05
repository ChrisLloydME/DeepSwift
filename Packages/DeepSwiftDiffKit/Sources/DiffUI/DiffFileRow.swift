//
//  DiffFileRow.swift
//  DiffUI
//

import DiffCore
import SwiftUI

/// Reusable changed-file row for native `List` sidebars.
public struct DiffFileRow: View {
    public let file: DiffSummaryFile

    public init(file: DiffSummaryFile) {
        self.file = file
    }

    public init(file: DiffFile) {
        self.file = DiffSummaryFile(file: file)
    }

    public var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 15)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.display)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if file.state != .modified {
                    Text(file.stateLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            DiffStatLabels(added: file.added, deleted: file.deleted)
        }
        .contentShape(Rectangle())
        .help(file.path)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(file.display), \(file.stateLabel), \(file.added) additions, \(file.deleted) deletions"
        )
    }

    private var icon: String {
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
