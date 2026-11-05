//
//  DiffModelAdapter.swift
//  DeepSwift
//
//  The only bridge between DSH workspace-change models and DiffCore. DiffCore
//  and DiffUI remain independent of the application and the Node Bridge.
//

import DiffCore
import Foundation

enum DiffModelAdapterError: LocalizedError, Equatable {
    case fileMismatch(expected: String, actual: String)
    case invalidFileIndex(Int)

    var errorDescription: String? {
        switch self {
        case let .fileMismatch(expected, actual):
            "The Host returned a comparison for \(actual) while \(expected) was requested."
        case let .invalidFileIndex(index):
            "The changed-file index \(index) is outside the captured summary."
        }
    }
}

enum DiffModelAdapter {
    /// Converts the compact Host summary to the model required by
    /// `DiffSummaryView`. The Host file order and authoritative statistics are
    /// preserved exactly.
    static func changeSummary(
        from summary: WorkspaceChangesSummary,
        reviewID: ReviewIdentity? = nil
    ) -> DiffChangeSummary {
        DiffChangeSummary(
            id: reviewID?.stableIdentifier ?? "changes",
            turn: summary.turn,
            cwd: summary.cwd,
            files: summary.files.map { file in
                DiffSummaryFile(
                    id: file.path,
                    path: file.path,
                    display: file.display,
                    added: file.added,
                    deleted: file.deleted,
                    state: state(for: file)
                )
            },
            total: summary.total,
            added: summary.added,
            deleted: summary.deleted,
            statisticsAreAuthoritative: true
        )
    }

    /// Converts one on-demand Host comparison. `summaryFile` is the file at
    /// the same index in the captured summary, which is authoritative for
    /// order and statistics.
    static func fileSource(
        from detail: WorkspaceFileDiff,
        summaryFile: WorkspaceChangedFile
    ) throws -> DiffFileSource {
        if !detail.path.isEmpty, detail.path != summaryFile.path {
            throw DiffModelAdapterError.fileMismatch(expected: summaryFile.path, actual: detail.path)
        }

        let isBinary = summaryFile.binary == true || detail.kind.caseInsensitiveCompare("binary") == .orderedSame
        let isOversized = summaryFile.oversized == true || detail.kind.caseInsensitiveCompare("oversized") == .orderedSame

        // DiffCore treats nil hunks as unavailable. A coarse comparison with no
        // hunks is still a coarse result, so an explicit empty array preserves
        // that Host state instead of mislabeling it as unavailable.
        let hunks: [DiffHunkSource]?
        if let detailHunks = detail.hunks {
            hunks = detailHunks.map { hunk in
                DiffHunkSource(
                    oldStart: hunk.oldStart,
                    oldLines: hunk.oldLines,
                    newStart: hunk.newStart,
                    newLines: hunk.newLines,
                    lines: hunk.lines
                )
            }
        } else if detail.coarse == true {
            hunks = []
        } else {
            hunks = nil
        }

        return DiffFileSource(
            kind: detail.kind,
            path: summaryFile.path,
            display: summaryFile.display.isEmpty ? detail.display : summaryFile.display,
            before: detail.before,
            after: detail.after,
            hunks: hunks,
            coarse: detail.coarse,
            added: summaryFile.added,
            deleted: summaryFile.deleted,
            binary: isBinary ? true : nil,
            oversized: isOversized ? true : nil
        )
    }

    static func file(
        from detail: WorkspaceFileDiff,
        summaryFile: WorkspaceChangedFile
    ) throws -> DiffFile {
        DiffFile(source: try fileSource(from: detail, summaryFile: summaryFile))
    }

    /// Materializes a complete DiffCore document when the caller has loaded
    /// the selected comparisons. This is used by tests and by hosts that want
    /// the standalone review content; the native Review window renders each
    /// file lazily and does not wait for every comparison.
    static func document(
        from summary: WorkspaceChangesSummary,
        files: [DiffFile]
    ) -> DiffDocument {
        DiffDocument(
            files: files,
            totals: DiffTotals(
                total: summary.total,
                added: summary.added,
                deleted: summary.deleted
            ),
            turn: summary.turn,
            cwd: summary.cwd
        )
    }

    static func summaryFile(
        at index: Int,
        in summary: WorkspaceChangesSummary
    ) throws -> WorkspaceChangedFile {
        guard summary.files.indices.contains(index) else {
            throw DiffModelAdapterError.invalidFileIndex(index)
        }
        return summary.files[index]
    }

    private static func state(for file: WorkspaceChangedFile) -> DiffFileState {
        if file.binary == true { return .binary }
        if file.oversized == true { return .oversized }
        return .modified
    }
}
