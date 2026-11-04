//
//  DiffPreviewFixtures.swift
//  DiffUI
//

#if DEBUG
import DiffCore
import SwiftUI

/// Synthetic, deterministic fixtures for previews. No user workspace, Host,
/// or private source code is involved.
enum DiffPreviewFixtures {
    static let richFile: DiffFile = {
        let first = DiffHunkSource(
            oldStart: 1,
            oldLines: 9,
            newStart: 1,
            newLines: 11,
            lines: [
                " import Foundation",
                " ",
                " struct DiffPreview {",
                "-    let maximum = 100",
                "+    let maximum = 200",
                "+    let label = \"Liquid Glass\"",
                "     let items: [String] = []",
                "     func value() -> Int { maximum }",
                "-    func title() -> String { \"Old\" }",
                "+    func title() -> String { \"Updated\" }",
                " }"
            ]
        )
        let second = DiffHunkSource(
            oldStart: 24,
            oldLines: 5,
            newStart: 26,
            newLines: 7,
            lines: [
                "     // Unicode stays intact.",
                "-    let greeting = \"hello 👋🏽\"",
                "+    let greeting = \"hello 🌍\"",
                "+    let punctuation = \"—\"",
                "     let done = true",
                "-    return greeting",
                "+    return greeting + punctuation"
            ]
        )
        return DiffFile(source: DiffFileSource(
            kind: "text",
            path: "Sources/DiffPreview/DiffPreview.swift",
            display: "Sources/DiffPreview/DiffPreview.swift",
            before: true,
            after: true,
            hunks: [first, second],
            added: 5,
            deleted: 3
        ))
    }()

    static let addedFile = DiffFile(source: DiffFileSource(
        kind: "text",
        path: "Sources/DiffPreview/NewFile.swift",
        display: "Sources/DiffPreview/NewFile.swift",
        before: false,
        after: true,
        hunks: [
            DiffHunkSource(
                oldStart: 0,
                oldLines: 0,
                newStart: 1,
                newLines: 4,
                lines: [
                    "+import Foundation",
                    "+",
                    "+struct NewFile {",
                    "+    static let value = 42"
                ]
            )
        ],
        added: 4,
        deleted: 0
    ))

    static let deletedFile = DiffFile(source: DiffFileSource(
        kind: "text",
        path: "Sources/Deprecated/OldView.swift",
        display: "Sources/Deprecated/OldView.swift",
        before: true,
        after: false,
        hunks: [
            DiffHunkSource(
                oldStart: 1,
                oldLines: 3,
                newStart: 0,
                newLines: 0,
                lines: ["-import SwiftUI", "-", "-struct OldView {}"]
            )
        ],
        added: 0,
        deleted: 3
    ))

    static let emptyFile = DiffFile(
        path: "Sources/DiffPreview/Empty.swift",
        before: true,
        after: true,
        hunks: [],
        added: 0,
        deleted: 0
    )

    static let binaryFile = DiffFile(
        path: "Assets/PreviewLogo.png",
        before: true,
        after: true,
        added: 0,
        deleted: 0,
        binary: true
    )

    static let oversizedFile = DiffFile(
        path: "Sources/DiffPreview/Generated.generated.swift",
        before: true,
        after: true,
        added: 0,
        deleted: 0,
        oversized: true
    )

    static let unavailableFile = DiffFile(
        path: "Sources/DiffPreview/MissingSnapshot.swift",
        before: true,
        after: true,
        added: 0,
        deleted: 0,
        unavailable: true
    )

    static let coarseFile = DiffFile(
        path: "Sources/DiffPreview/Coarse.swift",
        before: true,
        after: true,
        hunks: [
            DiffHunkParser.parse(
                lines: ["-old contents", "+new contents"],
                oldStart: 1,
                oldLines: 1,
                newStart: 1,
                newLines: 1,
                index: 0
            )
        ],
        coarse: true,
        added: 1,
        deleted: 1
    )

    static let files: [DiffFile] = [
        richFile,
        addedFile,
        deletedFile,
        emptyFile,
        binaryFile,
        oversizedFile,
        unavailableFile,
        coarseFile
    ]

    static let document = DiffDocument(
        files: files,
        totals: DiffTotals(total: files.count, added: 13, deleted: 10),
        turn: 12,
        cwd: "/Users/example/DeepSwiftDiffKit"
    )

    static let summary = DiffChangeSummary(
        turn: 12,
        cwd: "/Users/example/DeepSwiftDiffKit",
        files: files.map(DiffSummaryFile.init(file:)),
        total: files.count,
        added: 13,
        deleted: 10
    )
}

#if DEBUG
#Preview("Diff Summary — Light") {
    DiffSummaryView(summary: DiffPreviewFixtures.summary, onReview: {})
        .padding(24)
        .frame(width: 760)
        .preferredColorScheme(.light)
}

#Preview("Diff Summary — Dark") {
    DiffSummaryView(summary: DiffPreviewFixtures.summary, onReview: {})
        .padding(24)
        .frame(width: 760)
        .preferredColorScheme(.dark)
}

#Preview("Unified Diff — Light") {
    UnifiedDiffView(file: DiffPreviewFixtures.richFile)
        .frame(width: 960, height: 620)
        .preferredColorScheme(.light)
}

#Preview("Unified Diff — Dark") {
    UnifiedDiffView(file: DiffPreviewFixtures.richFile)
        .frame(width: 960, height: 620)
        .preferredColorScheme(.dark)
}

#Preview("Side by Side — Light") {
    SideBySideDiffView(file: DiffPreviewFixtures.richFile)
        .frame(width: 1_000, height: 620)
        .preferredColorScheme(.light)
}

#Preview("Side by Side — Dark") {
    SideBySideDiffView(file: DiffPreviewFixtures.richFile)
        .frame(width: 1_000, height: 620)
        .preferredColorScheme(.dark)
}

#Preview("Diff Review — Light") {
    DiffReviewView(document: DiffPreviewFixtures.document)
        .frame(width: 1_100, height: 700)
        .preferredColorScheme(.light)
}

#Preview("Diff Review — Dark") {
    DiffReviewView(document: DiffPreviewFixtures.document)
        .frame(width: 1_100, height: 700)
        .preferredColorScheme(.dark)
}

#Preview("Diff Review — Side by Side") {
    DiffReviewView(
        document: DiffPreviewFixtures.document,
        initialMode: .sideBySide
    )
    .frame(width: 1_100, height: 700)
    .preferredColorScheme(.light)
}

#Preview("Diff Review — Binary File") {
    DiffReviewView(
        document: DiffPreviewFixtures.document,
        initialFileID: DiffPreviewFixtures.binaryFile.id
    )
    .frame(width: 1_100, height: 700)
    .preferredColorScheme(.light)
}
#endif
#endif
