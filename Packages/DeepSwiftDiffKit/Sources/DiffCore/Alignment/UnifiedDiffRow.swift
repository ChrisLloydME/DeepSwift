//
//  UnifiedDiffRow.swift
//  DiffCore
//

import Foundation

public enum UnifiedDiffRowContent: Hashable, Sendable {
    case hunkHeader(hunkIndex: Int, header: String)
    case line(DiffLine)
}

public enum UnifiedDiffRowID: Hashable, Sendable {
    case hunkHeader(Int)
    case line(DiffLineID)
}

public struct UnifiedDiffRow: Identifiable, Hashable, Sendable {
    public let id: UnifiedDiffRowID
    public let hunkIndex: Int
    public let content: UnifiedDiffRowContent
    public let intralineSpans: [DiffTextSpan]

    public init(
        hunkIndex: Int,
        content: UnifiedDiffRowContent,
        intralineSpans: [DiffTextSpan] = []
    ) {
        self.hunkIndex = hunkIndex
        self.content = content
        self.intralineSpans = intralineSpans
        switch content {
        case let .hunkHeader(index, _):
            id = .hunkHeader(index)
        case let .line(line):
            id = .line(line.id)
        }
    }

    public var line: DiffLine? {
        if case let .line(line) = content { return line }
        return nil
    }

    public var header: String? {
        if case let .hunkHeader(_, header) = content { return header }
        return nil
    }

    public var isHunkHeader: Bool {
        header != nil
    }
}

public enum UnifiedDiffBuilder {
    /// Builds the ordered presentation rows for one file. Hunk headers are
    /// included as ordinary rows so scrolling and hunk navigation share one
    /// coordinate system.
    public static func rows(
        for file: DiffFile,
        intraline: IntralineOptions = .default
    ) -> [UnifiedDiffRow] {
        var rows: [UnifiedDiffRow] = []
        for hunk in file.hunks {
            rows.append(UnifiedDiffRow(
                hunkIndex: hunk.id,
                content: .hunkHeader(hunkIndex: hunk.id, header: hunk.header)
            ))
            let spans = intraline.isEnabled
                ? IntralineDiffer.spansByLineID(in: hunk, options: intraline)
                : [:]
            for line in hunk.lines {
                rows.append(UnifiedDiffRow(
                    hunkIndex: hunk.id,
                    content: .line(line),
                    intralineSpans: spans[line.id] ?? []
                ))
            }
        }
        return rows
    }

    public static func hunkRowIndices(in rows: [UnifiedDiffRow]) -> [Int: Int] {
        var result: [Int: Int] = [:]
        for (index, row) in rows.enumerated() where row.isHunkHeader {
            result[row.hunkIndex] = index
        }
        return result
    }
}
