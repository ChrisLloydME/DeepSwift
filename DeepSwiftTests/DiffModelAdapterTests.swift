//
//  DiffModelAdapterTests.swift
//  DeepSwiftTests
//

import DiffCore
import Foundation
import Testing
@testable import DeepSwift

@Suite("Diff model adapter")
struct DiffModelAdapterTests {
    private let summary = WorkspaceChangesSummary(
        turn: 4,
        cwd: "/Users/example/Project",
        files: [
            WorkspaceChangedFile(
                path: "Sources/Zeta.swift",
                display: "Zeta.swift",
                added: 43,
                deleted: 7,
                binary: nil,
                oversized: nil
            ),
            WorkspaceChangedFile(
                path: "Sources/Alpha.swift",
                display: "Alpha.swift",
                added: 2,
                deleted: 2,
                binary: nil,
                oversized: nil
            ),
            WorkspaceChangedFile(
                path: "Assets/logo.png",
                display: "logo.png",
                added: 0,
                deleted: 0,
                binary: true,
                oversized: nil
            ),
            WorkspaceChangedFile(
                path: "Assets/archive.bin",
                display: "archive.bin",
                added: 0,
                deleted: 0,
                binary: nil,
                oversized: true
            )
        ],
        total: 4,
        added: 45,
        deleted: 9
    )

    private let identity = ReviewIdentity(sessionID: "session-a", sequence: 42, turn: 4)

    @Test("Summary conversion preserves order, totals, and file state")
    func summaryConversion() {
        let converted = DiffModelAdapter.changeSummary(from: summary, reviewID: identity)

        #expect(converted.id == "session-a#42")
        #expect(converted.turn == 4)
        #expect(converted.cwd == "/Users/example/Project")
        #expect(converted.files.map(\.path) == summary.files.map(\.path))
        #expect(converted.total == 4)
        #expect(converted.added == 45)
        #expect(converted.deleted == 9)
        #expect(converted.statisticsAreAuthoritative)
        #expect(converted.files[0].added == 43)
        #expect(converted.files[0].deleted == 7)
        #expect(converted.files[2].state == .binary)
        #expect(converted.files[3].state == .oversized)
    }

    @Test("Stable summary indices are not sorted")
    func stableIndices() throws {
        // The Host index refers to the summary array, not a sorted projection.
        let first = try DiffModelAdapter.summaryFile(at: 0, in: summary)
        let second = try DiffModelAdapter.summaryFile(at: 1, in: summary)
        #expect(first.path == "Sources/Zeta.swift")
        #expect(second.path == "Sources/Alpha.swift")
        #expect(throws: DiffModelAdapterError.invalidFileIndex(4)) {
            try DiffModelAdapter.summaryFile(at: 4, in: summary)
        }
    }

    @Test("Detail conversion preserves hunks and Host statistics")
    func detailConversion() throws {
        let detail = WorkspaceFileDiff(
            kind: "text",
            path: "Sources/Zeta.swift",
            display: "Zeta.swift",
            before: true,
            after: true,
            hunks: [
                WorkspaceDiffHunk(
                    oldStart: 10,
                    oldLines: 2,
                    newStart: 10,
                    newLines: 3,
                    lines: [
                        " let title = \"Welcome\"",
                        "-let count = 1",
                        "+let count = 2",
                        "+let subtitle = \"Diff\""
                    ]
                )
            ],
            coarse: nil
        )

        let file = try DiffModelAdapter.file(from: detail, summaryFile: summary.files[0])

        #expect(file.path == "Sources/Zeta.swift")
        #expect(file.display == "Zeta.swift")
        #expect(file.kind == "text")
        #expect(file.before == true)
        #expect(file.after == true)
        #expect(file.hunks.count == 1)
        #expect(file.hunks[0].oldStart == 10)
        #expect(file.hunks[0].newLines == 3)
        #expect(file.hunks[0].lines.count == 4)
        // Host counts remain authoritative even though the hunk implies one
        // addition and one deletion.
        #expect(file.added == 43)
        #expect(file.deleted == 7)
        #expect(file.statisticsAreAuthoritative)
    }

    @Test("Coarse, binary, oversized, and unavailable states remain distinct")
    func specialStates() throws {
        let coarse = try DiffModelAdapter.file(
            from: WorkspaceFileDiff(
                kind: "text",
                path: "Sources/Zeta.swift",
                display: "Zeta.swift",
                before: true,
                after: true,
                hunks: [
                    WorkspaceDiffHunk(oldStart: 1, oldLines: 1, newStart: 1, newLines: 1, lines: ["-old", "+new"])
                ],
                coarse: true
            ),
            summaryFile: summary.files[0]
        )
        #expect(coarse.state == .coarse)

        let coarseWithoutHunks = try DiffModelAdapter.file(
            from: WorkspaceFileDiff(
                kind: "text",
                path: "Sources/Zeta.swift",
                display: "Zeta.swift",
                before: true,
                after: true,
                hunks: nil,
                coarse: true
            ),
            summaryFile: summary.files[0]
        )
        #expect(coarseWithoutHunks.state == .coarse)
        #expect(coarseWithoutHunks.isUnavailable == false)

        let binary = try DiffModelAdapter.file(
            from: WorkspaceFileDiff(
                kind: "binary",
                path: "Assets/logo.png",
                display: "logo.png",
                before: true,
                after: true,
                hunks: nil,
                coarse: nil
            ),
            summaryFile: summary.files[2]
        )
        #expect(binary.state == .binary)
        #expect(binary.isUnavailable == false)

        let oversized = try DiffModelAdapter.file(
            from: WorkspaceFileDiff(
                kind: "oversized",
                path: "Assets/archive.bin",
                display: "archive.bin",
                before: true,
                after: true,
                hunks: nil,
                coarse: nil
            ),
            summaryFile: summary.files[3]
        )
        #expect(oversized.state == .oversized)
        #expect(oversized.isUnavailable == false)

        let unavailable = try DiffModelAdapter.file(
            from: WorkspaceFileDiff(
                kind: "unavailable",
                path: "Sources/Zeta.swift",
                display: "Zeta.swift",
                before: nil,
                after: nil,
                hunks: nil,
                coarse: nil
            ),
            summaryFile: summary.files[0]
        )
        #expect(unavailable.state == .unavailable)
    }

    @Test("A mismatched detail path is rejected")
    func pathMismatch() {
        let detail = WorkspaceFileDiff(
            kind: "text",
            path: "Sources/Other.swift",
            display: "Other.swift",
            before: true,
            after: true,
            hunks: [],
            coarse: nil
        )

        #expect(throws: DiffModelAdapterError.fileMismatch(
            expected: "Sources/Zeta.swift",
            actual: "Sources/Other.swift"
        )) {
            try DiffModelAdapter.file(from: detail, summaryFile: summary.files[0])
        }
    }

    @Test("Document totals come from the captured summary")
    func documentConversion() throws {
        let file = try DiffModelAdapter.file(
            from: WorkspaceFileDiff(
                kind: "text",
                path: "Sources/Alpha.swift",
                display: "Alpha.swift",
                before: true,
                after: true,
                hunks: [
                    WorkspaceDiffHunk(oldStart: 1, oldLines: 1, newStart: 1, newLines: 1, lines: ["-a", "+b"])
                ],
                coarse: nil
            ),
            summaryFile: summary.files[1]
        )

        let document = DiffModelAdapter.document(
            from: summary,
            files: [file]
        )

        #expect(document.files.map(\.path) == ["Sources/Alpha.swift"])
        #expect(document.turn == 4)
        #expect(document.cwd == "/Users/example/Project")
        #expect(document.totals?.total == 4)
        #expect(document.totals?.added == 45)
        #expect(document.totals?.deleted == 9)
    }
}
