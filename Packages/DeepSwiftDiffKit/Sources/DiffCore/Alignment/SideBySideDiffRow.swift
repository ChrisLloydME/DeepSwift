//
//  SideBySideDiffRow.swift
//  DiffCore
//

import Foundation

public struct SideBySideDiffCell: Hashable, Sendable {
    public let line: DiffLine
    public let intralineSpans: [DiffTextSpan]

    public init(line: DiffLine, intralineSpans: [DiffTextSpan] = []) {
        self.line = line
        self.intralineSpans = intralineSpans
    }

    public var lineNumber: Int? { line.oldLineNumber ?? line.newLineNumber }
}

public enum SideBySideDiffRowContent: Hashable, Sendable {
    case hunkHeader(hunkIndex: Int, header: String)
    case pair(left: SideBySideDiffCell?, right: SideBySideDiffCell?)
    case unknown(DiffLine)
}

public struct SideBySideDiffRowID: Hashable, Sendable {
    public let hunkIndex: Int
    public let ordinal: Int

    public init(hunkIndex: Int, ordinal: Int) {
        self.hunkIndex = hunkIndex
        self.ordinal = ordinal
    }
}

public struct SideBySideDiffRow: Identifiable, Hashable, Sendable {
    public let id: SideBySideDiffRowID
    public let hunkIndex: Int
    public let content: SideBySideDiffRowContent

    public init(hunkIndex: Int, ordinal: Int, content: SideBySideDiffRowContent) {
        id = SideBySideDiffRowID(hunkIndex: hunkIndex, ordinal: ordinal)
        self.hunkIndex = hunkIndex
        self.content = content
    }

    public var isHunkHeader: Bool {
        if case .hunkHeader = content { return true }
        return false
    }

    public var header: String? {
        if case let .hunkHeader(_, header) = content { return header }
        return nil
    }

    public var left: SideBySideDiffCell? {
        if case let .pair(left, _) = content { return left }
        return nil
    }

    public var right: SideBySideDiffCell? {
        if case let .pair(_, right) = content { return right }
        return nil
    }
}

public enum SideBySideDiffBuilder {
    /// Aligns each hunk into a shared logical row sequence.
    ///
    /// Consecutive deletion/addition runs are separated into their respective
    /// ordered streams and paired by position. Exhausted sides become an empty
    /// placeholder cell; no deletion is paired with an unrelated addition from
    /// a different region.
    public static func rows(
        for file: DiffFile,
        intraline: IntralineOptions = .default
    ) -> [SideBySideDiffRow] {
        var rows: [SideBySideDiffRow] = []

        for hunk in file.hunks {
            rows.append(SideBySideDiffRow(
                hunkIndex: hunk.id,
                ordinal: 0,
                content: .hunkHeader(hunkIndex: hunk.id, header: hunk.header)
            ))

            let spans = intraline.isEnabled
                ? IntralineDiffer.spansByLineID(in: hunk, options: intraline)
                : [:]
            var ordinal = 1
            var index = 0

            while index < hunk.lines.count {
                let line = hunk.lines[index]

                switch line.kind {
                case .context:
                    rows.append(SideBySideDiffRow(
                        hunkIndex: hunk.id,
                        ordinal: ordinal,
                        content: .pair(
                            left: SideBySideDiffCell(line: line),
                            right: SideBySideDiffCell(line: line)
                        )
                    ))
                    ordinal += 1
                    index += 1

                case .unknown:
                    rows.append(SideBySideDiffRow(
                        hunkIndex: hunk.id,
                        ordinal: ordinal,
                        content: .unknown(line)
                    ))
                    ordinal += 1
                    index += 1

                case .deletion, .addition:
                    var deletions: [DiffLine] = []
                    var additions: [DiffLine] = []
                    while index < hunk.lines.count {
                        let change = hunk.lines[index]
                        switch change.kind {
                        case .deletion:
                            deletions.append(change)
                        case .addition:
                            additions.append(change)
                        case .context, .unknown:
                            break
                        }
                        if change.kind == .context || change.kind == .unknown {
                            break
                        }
                        index += 1
                    }

                    let pairTotal = max(deletions.count, additions.count)
                    for pairIndex in 0..<pairTotal {
                        let deletion = pairIndex < deletions.count ? deletions[pairIndex] : nil
                        let addition = pairIndex < additions.count ? additions[pairIndex] : nil
                        rows.append(SideBySideDiffRow(
                            hunkIndex: hunk.id,
                            ordinal: ordinal,
                            content: .pair(
                                left: deletion.map {
                                    SideBySideDiffCell(
                                        line: $0,
                                        intralineSpans: spans[$0.id] ?? []
                                    )
                                },
                                right: addition.map {
                                    SideBySideDiffCell(
                                        line: $0,
                                        intralineSpans: spans[$0.id] ?? []
                                    )
                                }
                            )
                        ))
                        ordinal += 1
                    }
                }
            }
        }

        return rows
    }

    public static func hunkRowIndices(in rows: [SideBySideDiffRow]) -> [Int: Int] {
        var result: [Int: Int] = [:]
        for (index, row) in rows.enumerated() where row.isHunkHeader {
            result[row.hunkIndex] = index
        }
        return result
    }
}
