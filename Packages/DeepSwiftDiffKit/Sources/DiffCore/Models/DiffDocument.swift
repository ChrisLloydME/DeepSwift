//
//  DiffDocument.swift
//  DiffCore
//

import Foundation

public struct DiffTotals: Hashable, Sendable {
    public let total: Int
    public let added: Int
    public let deleted: Int
    public let statisticsAreAuthoritative: Bool

    public init(
        total: Int,
        added: Int,
        deleted: Int,
        statisticsAreAuthoritative: Bool = true
    ) {
        self.total = max(0, total)
        self.added = max(0, added)
        self.deleted = max(0, deleted)
        self.statisticsAreAuthoritative = statisticsAreAuthoritative
    }
}

/// A complete, in-memory Diff document. DiffCore never fetches a document from
/// DSH or recomputes a source diff; callers provide materialized Host data.
public struct DiffDocument: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let files: [DiffFile]
    public let totals: DiffTotals?
    public let turn: Int?
    public let cwd: String?

    public init(
        files: [DiffFile],
        totals: DiffTotals? = nil,
        turn: Int? = nil,
        cwd: String? = nil,
        id: UUID = UUID()
    ) {
        self.id = id
        self.files = files
        self.totals = totals
        self.turn = turn
        self.cwd = cwd
    }

    public init(
        sources: [DiffFileSource],
        totals: DiffTotals? = nil,
        turn: Int? = nil,
        cwd: String? = nil,
        id: UUID = UUID()
    ) {
        self.init(
            files: sources.map(DiffFile.init(source:)),
            totals: totals,
            turn: turn,
            cwd: cwd,
            id: id
        )
    }

    public var fileCount: Int { files.count }

    public var summary: DiffChangeSummary {
        DiffChangeSummary(
            turn: turn,
            cwd: cwd,
            files: files.map(DiffSummaryFile.init(file:)),
            total: totals?.total ?? files.count,
            added: totals?.added ?? files.reduce(0) { $0 + $1.added },
            deleted: totals?.deleted ?? files.reduce(0) { $0 + $1.deleted },
            statisticsAreAuthoritative: totals?.statisticsAreAuthoritative ?? files.allSatisfy(\.statisticsAreAuthoritative)
        )
    }
}

/// One compact changed-file row. It intentionally does not require the full
/// hunk payload, so a summary can be rendered before details are loaded.
public struct DiffSummaryFile: Identifiable, Hashable, Sendable {
    public let id: String
    public let path: String
    public let display: String
    public let added: Int
    public let deleted: Int
    public let state: DiffFileState

    public init(
        id: String? = nil,
        path: String,
        display: String? = nil,
        added: Int,
        deleted: Int,
        state: DiffFileState = .modified
    ) {
        self.id = id ?? path
        self.path = path
        self.display = display?.isEmpty == false ? display! : path
        self.added = max(0, added)
        self.deleted = max(0, deleted)
        self.state = state
    }

    public init(file: DiffFile) {
        self.init(
            id: file.id,
            path: file.path,
            display: file.display,
            added: file.added,
            deleted: file.deleted,
            state: file.state
        )
    }

    public var stateLabel: String {
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

/// Generic summary accepted by `DiffSummaryView`. The authoritative Host
/// totals are retained even when `files` is a truncated preview.
public struct DiffChangeSummary: Identifiable, Hashable, Sendable {
    public let id: String
    public let turn: Int?
    public let cwd: String?
    public let files: [DiffSummaryFile]
    public let total: Int
    public let added: Int
    public let deleted: Int
    public let statisticsAreAuthoritative: Bool

    public init(
        id: String = "changes",
        turn: Int? = nil,
        cwd: String? = nil,
        files: [DiffSummaryFile],
        total: Int? = nil,
        added: Int? = nil,
        deleted: Int? = nil,
        statisticsAreAuthoritative: Bool = true
    ) {
        self.id = id
        self.turn = turn
        self.cwd = cwd
        self.files = files
        self.total = max(0, total ?? files.count)
        self.added = max(0, added ?? files.reduce(0) { $0 + $1.added })
        self.deleted = max(0, deleted ?? files.reduce(0) { $0 + $1.deleted })
        self.statisticsAreAuthoritative = statisticsAreAuthoritative
    }

    public var fileCount: Int { total }
    public var hasFiles: Bool { !files.isEmpty }
    public var isTruncated: Bool { files.count < total }
}
