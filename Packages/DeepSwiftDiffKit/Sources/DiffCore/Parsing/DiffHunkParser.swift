//
//  DiffHunkParser.swift
//  DiffCore
//

import Foundation

/// Converts DSH's prefixed hunk records into typed lines.
///
/// The parser is deliberately tolerant. A malformed record is retained as an
/// `unknown` line instead of causing its hunk or neighboring valid lines to be
/// discarded. Prefix characters are never included in `DiffLine.text`.
public enum DiffHunkParser {
    public static func parse(_ source: DiffHunkSource, index: Int) -> DiffHunk {
        var lines: [DiffLine] = []
        lines.reserveCapacity(source.lines.count)
        var oldNumber = source.oldStart
        var newNumber = source.newStart

        for (lineIndex, record) in source.lines.enumerated() {
            let id = DiffLineID(hunk: index, index: lineIndex)
            guard let prefix = record.first else {
                lines.append(DiffLine(id: id, kind: .unknown, text: record))
                continue
            }

            switch prefix {
            case " ":
                lines.append(DiffLine(
                    id: id,
                    kind: .context,
                    text: String(record.dropFirst()),
                    oldLineNumber: oldNumber,
                    newLineNumber: newNumber
                ))
                oldNumber += 1
                newNumber += 1
            case "+":
                lines.append(DiffLine(
                    id: id,
                    kind: .addition,
                    text: String(record.dropFirst()),
                    oldLineNumber: nil,
                    newLineNumber: newNumber
                ))
                newNumber += 1
            case "-":
                lines.append(DiffLine(
                    id: id,
                    kind: .deletion,
                    text: String(record.dropFirst()),
                    oldLineNumber: oldNumber,
                    newLineNumber: nil
                ))
                oldNumber += 1
            default:
                // This includes "\ No newline at end of file" and extension
                // records. Preserve the record without inventing line numbers.
                lines.append(DiffLine(id: id, kind: .unknown, text: record))
            }
        }

        return DiffHunk(
            id: index,
            oldStart: source.oldStart,
            oldLines: source.oldLines,
            newStart: source.newStart,
            newLines: source.newLines,
            lines: lines
        )
    }

    public static func parse(
        lines: [String],
        oldStart: Int,
        oldLines: Int,
        newStart: Int,
        newLines: Int,
        index: Int
    ) -> DiffHunk {
        parse(
            DiffHunkSource(
                oldStart: oldStart,
                oldLines: oldLines,
                newStart: newStart,
                newLines: newLines,
                lines: lines
            ),
            index: index
        )
    }
}
