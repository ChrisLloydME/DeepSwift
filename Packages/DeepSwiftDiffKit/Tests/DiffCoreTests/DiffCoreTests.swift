import XCTest
@testable import DiffCore

final class DiffCoreTests: XCTestCase {
    // MARK: - Parsing

    func testHunkParsingComputesBothLineNumberStreams() {
        let hunk = DiffHunkParser.parse(
            lines: [
                " let title = \"Welcome\"",
                "-let count = 1",
                "+let count = 2",
                "+print(count)",
                " return title"
            ],
            oldStart: 10,
            oldLines: 3,
            newStart: 10,
            newLines: 4,
            index: 0
        )

        XCTAssertEqual(hunk.lines.map(\.kind), [.context, .deletion, .addition, .addition, .context])
        XCTAssertEqual(hunk.lines.map(\.text), [
            "let title = \"Welcome\"",
            "let count = 1",
            "let count = 2",
            "print(count)",
            "return title"
        ])
        XCTAssertEqual(hunk.lines.map(\.oldLineNumber), [10, 11, nil, nil, 12])
        XCTAssertEqual(hunk.lines.map(\.newLineNumber), [10, nil, 11, 12, 13])
        XCTAssertEqual(hunk.header, "@@ -10,3 +10,4 @@")
    }

    func testMalformedRecordIsPreservedWithoutInventingNumbers() {
        let hunk = DiffHunkParser.parse(
            lines: [
                " context",
                "not-prefixed",
                "\\ No newline at end of file",
                "+added",
                "",
                "-removed"
            ],
            oldStart: 1,
            oldLines: 3,
            newStart: 1,
            newLines: 2,
            index: 2
        )

        XCTAssertEqual(hunk.lines.count, 6)
        XCTAssertEqual(hunk.lines[0].kind, .context)
        XCTAssertEqual(hunk.lines[1].kind, .unknown)
        XCTAssertEqual(hunk.lines[1].text, "not-prefixed")
        XCTAssertNil(hunk.lines[1].oldLineNumber)
        XCTAssertNil(hunk.lines[1].newLineNumber)
        XCTAssertEqual(hunk.lines[2].kind, .unknown)
        XCTAssertEqual(hunk.lines[3].kind, .addition)
        XCTAssertEqual(hunk.lines[3].newLineNumber, 2)
        XCTAssertEqual(hunk.lines[4].kind, .unknown)
        XCTAssertEqual(hunk.lines[5].kind, .deletion)
        XCTAssertEqual(hunk.lines[5].oldLineNumber, 2)
    }

    func testPrefixedEmptyLinesAreRealLines() {
        let hunk = DiffHunkParser.parse(
            lines: ["+", "-", " "],
            oldStart: 4,
            oldLines: 2,
            newStart: 4,
            newLines: 2,
            index: 0
        )

        XCTAssertEqual(hunk.lines.map(\.text), ["", "", ""])
        XCTAssertEqual(hunk.lines.map(\.kind), [.addition, .deletion, .context])
        XCTAssertEqual(hunk.lines[0].newLineNumber, 4)
        XCTAssertEqual(hunk.lines[1].oldLineNumber, 4)
        XCTAssertEqual(hunk.lines[2].oldLineNumber, 5)
        XCTAssertEqual(hunk.lines[2].newLineNumber, 5)
    }

    // MARK: - Unified rows

    func testUnifiedRowsPreserveHunkBoundariesAndLineOrder() {
        let hunkOne = DiffHunkParser.parse(
            lines: [" context", "-old", "+new"],
            oldStart: 1,
            oldLines: 2,
            newStart: 1,
            newLines: 2,
            index: 0
        )
        let hunkTwo = DiffHunkParser.parse(
            lines: ["+added"],
            oldStart: 20,
            oldLines: 0,
            newStart: 20,
            newLines: 1,
            index: 1
        )
        let file = DiffFile(path: "Source.swift", hunks: [hunkOne, hunkTwo], added: 2, deleted: 1)
        let rows = UnifiedDiffBuilder.rows(for: file, intraline: .disabled)

        XCTAssertEqual(rows.map(\.hunkIndex), [0, 0, 0, 0, 1, 1])
        XCTAssertEqual(rows.map(\.isHunkHeader), [true, false, false, false, true, false])
        XCTAssertEqual(rows[0].header, "@@ -1,2 +1,2 @@")
        XCTAssertEqual(rows[1].line?.text, "context")
        XCTAssertEqual(rows[2].line?.kind, .deletion)
        XCTAssertEqual(rows[3].line?.kind, .addition)
        XCTAssertEqual(rows[4].header, "@@ -20,0 +20,1 @@")
        XCTAssertEqual(rows[5].line?.text, "added")
        XCTAssertEqual(UnifiedDiffBuilder.hunkRowIndices(in: rows), [0: 0, 1: 4])
    }

    func testUnifiedRowsAreStableAcrossRebuilds() {
        let file = makeFile()
        let first = UnifiedDiffBuilder.rows(for: file)
        let second = UnifiedDiffBuilder.rows(for: file)
        XCTAssertEqual(first.map(\.id), second.map(\.id))
    }

    // MARK: - Side-by-side alignment

    func testSideBySidePairsReplacementsInOrder() {
        let file = makeFile(
            lines: [
                " context",
                "-first old",
                "-second old",
                "+first new",
                "+second new",
                "+third new",
                " context 2"
            ],
            oldStart: 5,
            oldLines: 4,
            newStart: 5,
            newLines: 5
        )
        let rows = SideBySideDiffBuilder.rows(for: file, intraline: .disabled)
        let pairs = rows.compactMap { row -> (String?, String?)? in
            guard case let .pair(left, right) = row.content else { return nil }
            return (left?.line.text, right?.line.text)
        }

        XCTAssertEqual(pairs.count, 5)
        XCTAssertEqual(pairs[0].0, "context")
        XCTAssertEqual(pairs[0].1, "context")
        XCTAssertEqual(pairs[1].0, "first old")
        XCTAssertEqual(pairs[1].1, "first new")
        XCTAssertEqual(pairs[2].0, "second old")
        XCTAssertEqual(pairs[2].1, "second new")
        XCTAssertEqual(pairs[3].0, nil)
        XCTAssertEqual(pairs[3].1, "third new")
        XCTAssertEqual(pairs[4].0, "context 2")
        XCTAssertEqual(pairs[4].1, "context 2")
        XCTAssertEqual(rows.last?.left?.line.text, "context 2")
        XCTAssertEqual(rows.last?.right?.line.text, "context 2")
    }

    func testSideBySideUnequalDeletionRunUsesPlaceholders() {
        let file = makeFile(
            lines: ["-one", "-two", "-three", "+replacement"],
            oldStart: 1,
            oldLines: 3,
            newStart: 1,
            newLines: 1
        )
        let rows = SideBySideDiffBuilder.rows(for: file, intraline: .disabled)
        let pairs = rows.compactMap { row -> (String?, String?)? in
            guard case let .pair(left, right) = row.content else { return nil }
            return (left?.line.text, right?.line.text)
        }

        XCTAssertEqual(pairs.count, 3)
        XCTAssertEqual(pairs[0].0, "one")
        XCTAssertEqual(pairs[0].1, "replacement")
        XCTAssertEqual(pairs[1].0, "two")
        XCTAssertNil(pairs[1].1)
        XCTAssertEqual(pairs[2].0, "three")
        XCTAssertNil(pairs[2].1)
    }

    func testDeletionOnlyAndAdditionOnlyRegionsHaveEmptySides() {
        let file = makeFile(
            lines: ["-removed", "-more removed", "+added"],
            oldStart: 1,
            oldLines: 2,
            newStart: 1,
            newLines: 1
        )
        let rows = SideBySideDiffBuilder.rows(for: file, intraline: .disabled)
        let pairs = rows.compactMap { row -> (String?, String?)? in
            guard case let .pair(left, right) = row.content else { return nil }
            return (left?.line.text, right?.line.text)
        }

        XCTAssertEqual(pairs.count, 2)
        XCTAssertEqual(pairs.map { $0.0 }, ["removed", "more removed"])
        XCTAssertEqual(pairs.map { $0.1 }, ["added", nil])
    }

    func testMultipleHunksKeepHunkIDsAndOrdinalsStable() {
        let first = DiffHunkParser.parse(
            lines: ["-a", "+b"],
            oldStart: 1,
            oldLines: 1,
            newStart: 1,
            newLines: 1,
            index: 0
        )
        let second = DiffHunkParser.parse(
            lines: [" context", "+c"],
            oldStart: 30,
            oldLines: 1,
            newStart: 30,
            newLines: 2,
            index: 1
        )
        let file = DiffFile(path: "Multi.swift", hunks: [first, second], added: 2, deleted: 1)
        let rows = SideBySideDiffBuilder.rows(for: file, intraline: .disabled)

        XCTAssertEqual(rows.filter(\.isHunkHeader).map(\.hunkIndex), [0, 1])
        XCTAssertEqual(Set(rows.map(\.id)).count, rows.count)
        XCTAssertEqual(SideBySideDiffBuilder.hunkRowIndices(in: rows), [0: 0, 1: 2])
    }

    func testUnknownRecordsAreRenderedAsUnknownRows() {
        let hunk = DiffHunkParser.parse(
            lines: [" context", "malformed", "+ok"],
            oldStart: 1,
            oldLines: 1,
            newStart: 1,
            newLines: 2,
            index: 0
        )
        let file = DiffFile(path: "Malformed.swift", hunks: [hunk], added: 1, deleted: 0)
        let rows = SideBySideDiffBuilder.rows(for: file, intraline: .disabled)
        let unknown = rows.first { if case .unknown = $0.content { return true }; return false }
        XCTAssertNotNil(unknown)
        XCTAssertEqual(unknown?.hunkIndex, 0)
        XCTAssertEqual(unknown?.header, nil)
    }

    // MARK: - States and statistics

    func testFileStatesRemainDistinct() {
        XCTAssertEqual(makeSource(kind: "binary", before: true, after: true, hunks: nil, binary: true).state, .binary)
        XCTAssertEqual(makeSource(kind: "oversized", before: true, after: true, hunks: nil, oversized: true).state, .oversized)
        XCTAssertEqual(makeSource(kind: "text", before: true, after: true, hunks: nil).state, .unavailable)
        XCTAssertEqual(makeSource(kind: "unavailable", before: true, after: true, hunks: []).state, .unavailable)
        XCTAssertEqual(makeSource(kind: "text", before: false, after: true, hunks: []).state, .added)
        XCTAssertEqual(makeSource(kind: "text", before: true, after: false, hunks: []).state, .deleted)
        XCTAssertEqual(makeSource(kind: "text", before: true, after: true, hunks: [], coarse: true).state, .coarse)
        XCTAssertEqual(makeSource(kind: "text", before: true, after: true, hunks: []).state, .empty)
        XCTAssertEqual(makeSource(kind: "text", before: true, after: true, hunks: [DiffHunkSource(oldStart: 1, oldLines: 1, newStart: 1, newLines: 1, lines: ["+new"])]).state, .modified)
    }

    func testAuthoritativeStatisticsAreNeverReplacedByDerivedCounts() {
        let source = DiffFileSource(
            kind: "text",
            path: "Big.swift",
            hunks: [
                DiffHunkSource(oldStart: 1, oldLines: 0, newStart: 1, newLines: 1, lines: ["+one"])
            ],
            added: 99,
            deleted: 42
        )
        let file = DiffFile(source: source)
        XCTAssertEqual(file.added, 99)
        XCTAssertEqual(file.deleted, 42)
        XCTAssertTrue(file.statisticsAreAuthoritative)

        let derived = DiffFile(source: DiffFileSource(
            kind: "text",
            path: "Derived.swift",
            hunks: [
                DiffHunkSource(oldStart: 1, oldLines: 1, newStart: 1, newLines: 2, lines: ["-old", "+a", "+b"])
            ]
        ))
        XCTAssertEqual(derived.added, 2)
        XCTAssertEqual(derived.deleted, 1)
        XCTAssertFalse(derived.statisticsAreAuthoritative)
    }

    func testLargeHunkAlignmentKeepsStableUniqueRows() {
        var lines: [String] = []
        for index in 0..<600 {
            lines.append("-    let value\(index) = \(index)")
            lines.append("+    let value\(index) = \(index + 1)")
        }
        let hunk = DiffHunkParser.parse(
            lines: lines,
            oldStart: 1,
            oldLines: 600,
            newStart: 1,
            newLines: 600,
            index: 0
        )
        let file = DiffFile(path: "Large.swift", hunks: [hunk], added: 600, deleted: 600)
        let unified = UnifiedDiffBuilder.rows(for: file, intraline: .disabled)
        let sideBySide = SideBySideDiffBuilder.rows(for: file, intraline: .disabled)
        XCTAssertEqual(Set(unified.map(\.id)).count, unified.count)
        XCTAssertEqual(Set(sideBySide.map(\.id)).count, sideBySide.count)
        XCTAssertEqual(sideBySide.filter { if case .pair = $0.content { return true }; return false }.count, 600)
        XCTAssertEqual(UnifiedDiffBuilder.rows(for: file, intraline: .disabled).map(\.id), unified.map(\.id))
    }

    func testDocumentSummaryUsesHostTotalsWhenProvided() {
        let file = DiffFile(path: "A.swift", hunks: [makeHunk(lines: ["+a"])], added: 1, deleted: 0)
        let document = DiffDocument(
            files: [file],
            totals: DiffTotals(total: 3, added: 10, deleted: 4)
        )
        let summary = document.summary
        XCTAssertEqual(summary.total, 3)
        XCTAssertEqual(summary.added, 10)
        XCTAssertEqual(summary.deleted, 4)
        XCTAssertTrue(summary.isTruncated)
        XCTAssertEqual(summary.files.count, 1)
        XCTAssertEqual(summary.files.first?.display, "A.swift")
    }

    // MARK: - Intraline

    func testIntralineHighlightsOnlyChangedMiddleRanges() {
        let result = IntralineDiffer.compare(old: "let maximum = 100", new: "let maximum = 200")
        XCTAssertEqual(result.oldSpans.count, 1)
        XCTAssertEqual(result.newSpans.count, 1)
        XCTAssertEqual(result.oldSpans[0].length, 1)
        XCTAssertEqual(result.newSpans[0].length, 1)
        XCTAssertEqual(result.oldSpans[0].location, 14)
        XCTAssertEqual(result.newSpans[0].location, 14)
    }

    func testIntralineUsesUTF16RangesWithoutSplittingEmoji() {
        let old = "let greeting = \"hello 👋🏽\""
        let new = "let greeting = \"hello 🌍\""
        let result = IntralineDiffer.compare(old: old, new: new)
        XCTAssertEqual(result.oldSpans.count, 1)
        XCTAssertEqual(result.newSpans.count, 1)

        let oldNSString = old as NSString
        let newNSString = new as NSString
        XCTAssertTrue(result.oldSpans[0].nsRange.location >= 0)
        XCTAssertTrue(NSMaxRange(result.oldSpans[0].nsRange) <= oldNSString.length)
        XCTAssertTrue(NSMaxRange(result.newSpans[0].nsRange) <= newNSString.length)
        let emojiRange = oldNSString.range(of: "👋🏽")
        let intersection = NSIntersectionRange(result.oldSpans[0].nsRange, emojiRange)
        XCTAssertEqual(intersection.length, emojiRange.length)
    }

    func testIntralineHandlesPureInsertionAndDeletion() {
        let insertion = IntralineDiffer.compare(old: "abc", new: "abXYZc")
        XCTAssertTrue(insertion.oldSpans.isEmpty)
        XCTAssertEqual(insertion.newSpans.first?.length, 3)

        let deletion = IntralineDiffer.compare(old: "abXYZc", new: "abc")
        XCTAssertEqual(deletion.oldSpans.first?.length, 3)
        XCTAssertTrue(deletion.newSpans.isEmpty)
    }

    func testIntralineSkipsLongLinesAndDisabledMode() {
        let long = String(repeating: "a", count: 5_000)
        let result = IntralineDiffer.compare(
            old: long + "old",
            new: long + "new",
            options: IntralineOptions(maxLineLength: 100)
        )
        XCTAssertTrue(result.isEmpty)

        let disabled = IntralineDiffer.compare(
            old: "one",
            new: "two",
            options: .disabled
        )
        XCTAssertTrue(disabled.isEmpty)
    }

    func testIntralineMapPairsAdjacentReplacementRunsOnly() {
        let hunk = DiffHunkParser.parse(
            lines: ["-old one", "+new one", " context", "-old two", "+new two"],
            oldStart: 1,
            oldLines: 3,
            newStart: 1,
            newLines: 3,
            index: 0
        )
        let spans = IntralineDiffer.spansByLineID(in: hunk)
        XCTAssertEqual(spans.count, 4)
        XCTAssertFalse(spans[hunk.lines[0].id]?.isEmpty ?? true)
        XCTAssertFalse(spans[hunk.lines[1].id]?.isEmpty ?? true)
        XCTAssertFalse(spans[hunk.lines[3].id]?.isEmpty ?? true)
        XCTAssertFalse(spans[hunk.lines[4].id]?.isEmpty ?? true)
        XCTAssertNil(spans[hunk.lines[2].id])
    }

    // MARK: - Syntax tokens

    func testSyntaxTokensCoverKeywordsStringsCommentsAndTypes() {
        let single = "struct Example { let value: Int = 42 } // note"
        let tokens = SwiftSyntaxHighlighter.tokens(in: single)
        let kinds = tokens.map(\.kind)
        XCTAssertTrue(kinds.contains(.keyword))
        XCTAssertTrue(kinds.contains(.type))
        XCTAssertTrue(kinds.contains(.number))
        XCTAssertTrue(kinds.contains(.comment))
        XCTAssertEqual(tokens.first?.span.location, 0)
        XCTAssertTrue(tokens.allSatisfy { $0.span.location + $0.span.length <= (single as NSString).length })
    }

    func testSyntaxStringTokenDoesNotHighlightKeywordsInsideString() {
        let line = "let text = \"struct notAClass\""
        let tokens = SwiftSyntaxHighlighter.tokens(in: line)
        let stringToken = tokens.first { $0.kind == .string }
        XCTAssertNotNil(stringToken)
        XCTAssertFalse(tokens.contains { $0.kind == .keyword && $0.span.location > 10 })
    }

    // MARK: - Helpers

    private func makeHunk(
        lines: [String],
        oldStart: Int = 1,
        oldLines: Int? = nil,
        newStart: Int = 1,
        newLines: Int? = nil,
        index: Int = 0
    ) -> DiffHunk {
        DiffHunkParser.parse(
            lines: lines,
            oldStart: oldStart,
            oldLines: oldLines ?? lines.filter { $0.first == " " || $0.first == "-" }.count,
            newStart: newStart,
            newLines: newLines ?? lines.filter { $0.first == " " || $0.first == "+" }.count,
            index: index
        )
    }

    private func makeFile(
        path: String = "Example.swift",
        lines: [String] = ["-old", "+new"],
        oldStart: Int = 1,
        oldLines: Int = 1,
        newStart: Int = 1,
        newLines: Int = 1
    ) -> DiffFile {
        let hunk = makeHunk(
            lines: lines,
            oldStart: oldStart,
            oldLines: oldLines,
            newStart: newStart,
            newLines: newLines
        )
        return DiffFile(
            path: path,
            hunks: [hunk],
            added: hunk.addedCount,
            deleted: hunk.deletedCount
        )
    }

    private func makeSource(
        kind: String,
        before: Bool?,
        after: Bool?,
        hunks: [DiffHunkSource]?,
        coarse: Bool? = nil,
        binary: Bool? = nil,
        oversized: Bool? = nil
    ) -> DiffFile {
        DiffFile(source: DiffFileSource(
            kind: kind,
            path: "Example.swift",
            before: before,
            after: after,
            hunks: hunks,
            coarse: coarse,
            binary: binary,
            oversized: oversized
        ))
    }
}
