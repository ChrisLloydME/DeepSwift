//
//  ReviewIntegrationTests.swift
//  DeepSwiftTests
//

import DiffCore
import DiffUI
import Foundation
import Testing
@testable import DeepSwift

private enum ReviewTestError: LocalizedError, Equatable {
    case expired

    var errorDescription: String? { "The comparison is no longer available." }
}

@MainActor
private final class MockReviewDiffLoader: ReviewDiffLoading {
    struct Request: Equatable {
        let sessionID: String
        let sequence: Int
        let index: Int
    }

    private(set) var requests: [Request] = []
    var delays: [Int: Duration] = [:]
    var handler: ((Int) async throws -> WorkspaceFileDiff)?

    init(handler: ((Int) async throws -> WorkspaceFileDiff)? = nil) {
        self.handler = handler
    }

    func loadChangesDiff(
        sessionID: String,
        sequence: Int,
        index: Int
    ) async throws -> WorkspaceFileDiff {
        requests.append(Request(sessionID: sessionID, sequence: sequence, index: index))
        if let delay = delays[index] {
            try await Task.sleep(for: delay)
        }
        guard let handler else {
            throw ReviewTestError.expired
        }
        return try await handler(index)
    }
}

private func makeSummary() -> WorkspaceChangesSummary {
    WorkspaceChangesSummary(
        turn: 6,
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
            )
        ],
        total: 2,
        added: 45,
        deleted: 9
    )
}

private func makeDetail(
    path: String,
    kind: String = "text",
    hunks: [WorkspaceDiffHunk]? = [
        WorkspaceDiffHunk(oldStart: 1, oldLines: 1, newStart: 1, newLines: 1, lines: ["-old", "+new"])
    ]
) -> WorkspaceFileDiff {
    WorkspaceFileDiff(
        kind: kind,
        path: path,
        display: (path as NSString).lastPathComponent,
        before: true,
        after: true,
        hunks: hunks,
        coarse: nil
    )
}

private func makeRequest(
    sessionID: String = "session-a",
    sequence: Int = 42,
    summary: WorkspaceChangesSummary? = nil
) -> ReviewCoordinator.Request {
    let summary = summary ?? makeSummary()
    return ReviewCoordinator.Request(
        identity: ReviewIdentity(sessionID: sessionID, sequence: sequence, turn: summary.turn),
        summary: summary,
        sessionTitle: "Review Session"
    )
}

@Suite("Review identity and coordinator")
@MainActor
struct ReviewCoordinatorTests {
    @Test("Identity is Session and sequence; turn is descriptive only")
    func identityEquality() {
        let first = ReviewIdentity(sessionID: "session-a", sequence: 9, turn: 1)
        let second = ReviewIdentity(sessionID: "session-a", sequence: 9, turn: 99)
        let otherSession = ReviewIdentity(sessionID: "session-b", sequence: 9, turn: 1)
        let otherSequence = ReviewIdentity(sessionID: "session-a", sequence: 10, turn: 1)

        #expect(first == second)
        #expect(first.hashValue == second.hashValue)
        #expect(first != otherSession)
        #expect(first != otherSequence)
        #expect(first.stableIdentifier == "session-a#9")
    }

    @Test("Registering the same Review preserves its summary and selection")
    func sameReviewReusesRequest() {
        let coordinator = ReviewCoordinator()
        let summary = makeSummary()
        let identity = coordinator.register(
            sessionID: "session-a",
            sequence: 42,
            turn: 6,
            summary: summary,
            sessionTitle: "Session A",
            selecting: "Sources/Alpha.swift"
        )
        let firstRequest = coordinator.request(for: identity)
        let firstRevision = coordinator.selectionRevision(for: identity)

        coordinator.setMode(.sideBySide, for: identity)

        let reopened = coordinator.register(
            sessionID: "session-a",
            sequence: 42,
            turn: 6,
            summary: summary,
            sessionTitle: "Session A"
        )

        #expect(reopened == identity)
        #expect(coordinator.requests.count == 1)
        #expect(coordinator.request(for: identity) == firstRequest)
        #expect(coordinator.selection(for: identity) == "Sources/Alpha.swift")
        #expect(coordinator.selectionRevision(for: identity) == firstRevision)
        #expect(coordinator.mode(for: identity) == .sideBySide)
    }

    @Test("Selecting a file routes to the matching Review only")
    func fileSelectionRouting() {
        let coordinator = ReviewCoordinator()
        let summary = makeSummary()
        let first = coordinator.register(
            sessionID: "session-a",
            sequence: 1,
            turn: 1,
            summary: summary,
            sessionTitle: "Session A"
        )
        let second = coordinator.register(
            sessionID: "session-b",
            sequence: 2,
            turn: 1,
            summary: summary,
            sessionTitle: "Session B"
        )

        coordinator.setSelection("Sources/Alpha.swift", for: first)
        coordinator.setSelection("Sources/Missing.swift", for: first)

        #expect(coordinator.selection(for: first) == "Sources/Alpha.swift")
        #expect(coordinator.selection(for: second) == "Sources/Zeta.swift")
        #expect(coordinator.selectionRevision(for: first) == 1)
        #expect(coordinator.selectionRevision(for: second) == 0)
    }

    @Test("Releasing one Review leaves other windows independent")
    func releaseIsScoped() {
        let coordinator = ReviewCoordinator()
        let summary = makeSummary()
        let first = coordinator.register(
            sessionID: "session-a",
            sequence: 1,
            turn: 1,
            summary: summary,
            sessionTitle: "Session A",
            selecting: "Sources/Alpha.swift"
        )
        let second = coordinator.register(
            sessionID: "session-b",
            sequence: 2,
            turn: 2,
            summary: summary,
            sessionTitle: "Session B"
        )

        coordinator.release(first)

        #expect(coordinator.request(for: first) == nil)
        #expect(coordinator.selection(for: first) == nil)
        #expect(coordinator.request(for: second) != nil)
        #expect(coordinator.selection(for: second) == "Sources/Zeta.swift")
    }
}

@Suite("Review window model")
@MainActor
struct ReviewWindowModelTests {
    @Test("Initial selection defaults to the first Host file")
    func initialSelection() {
        let loader = MockReviewDiffLoader()
        let model = ReviewWindowModel(
            request: makeRequest(),
            loader: loader
        )

        #expect(model.selectedFileID == "Sources/Zeta.swift")
        #expect(model.selectedFileIndex == 0)
        #expect(model.summary.files.map(\.path) == ["Sources/Zeta.swift", "Sources/Alpha.swift"])
        #expect(model.state(for: 0) == .notRequested)
    }

    @Test("Requested initial file is honored when it exists")
    func requestedInitialFile() {
        let model = ReviewWindowModel(
            request: makeRequest(),
            initialFileID: "Sources/Alpha.swift",
            loader: MockReviewDiffLoader()
        )

        #expect(model.selectedFileID == "Sources/Alpha.swift")
        #expect(model.selectedFileIndex == 1)
    }

    @Test("Loading is context-explicit and caches successful comparisons")
    func contextExplicitLoadingAndCaching() async throws {
        let loader = MockReviewDiffLoader { index in
            makeDetail(path: index == 0 ? "Sources/Zeta.swift" : "Sources/Alpha.swift")
        }
        let model = ReviewWindowModel(
            request: makeRequest(sessionID: "session-a", sequence: 77),
            loader: loader
        )

        await model.loadSelectedFile()
        #expect(loader.requests == [
            .init(sessionID: "session-a", sequence: 77, index: 0)
        ])
        guard case let .loaded(zeta) = model.state(for: 0) else {
            Issue.record("Expected the selected comparison to load")
            return
        }
        #expect(zeta.path == "Sources/Zeta.swift")
        #expect(zeta.added == 43)
        #expect(zeta.deleted == 7)

        model.selectFile("Sources/Alpha.swift")
        await model.loadSelectedFile()
        #expect(loader.requests.map(\.index) == [0, 1])

        // Switching back uses the in-memory comparison and does not re-fetch.
        model.selectFile("Sources/Zeta.swift")
        await model.loadSelectedFile()
        #expect(loader.requests.map(\.index) == [0, 1])
        guard case let .loaded(again) = model.state(for: 0) else {
            Issue.record("Expected cached comparison")
            return
        }
        #expect(again.path == "Sources/Zeta.swift")
    }

    @Test("A late result cannot overwrite a newer selection")
    func rapidSelection() async throws {
        let loader = MockReviewDiffLoader { index in
            makeDetail(path: index == 0 ? "Sources/Zeta.swift" : "Sources/Alpha.swift")
        }
        loader.delays = [0: .milliseconds(120), 1: .milliseconds(10)]
        let model = ReviewWindowModel(
            request: makeRequest(),
            loader: loader
        )

        let firstLoad = Task { await model.loadSelectedFile() }
        try await Task.sleep(for: .milliseconds(20))
        model.selectFile("Sources/Alpha.swift")
        await model.loadSelectedFile()
        await firstLoad.value

        #expect(model.selectedFileID == "Sources/Alpha.swift")
        guard case let .loaded(alpha) = model.state(for: 1) else {
            Issue.record("Expected the newer selection to be loaded")
            return
        }
        #expect(alpha.path == "Sources/Alpha.swift")
        #expect(model.state(for: 0) == .notRequested)
    }

    @Test("Cancellation clears loading state without surfacing an error")
    func cancellation() async throws {
        let loader = MockReviewDiffLoader { index in
            makeDetail(path: "Sources/Zeta.swift")
        }
        loader.delays = [0: .seconds(5)]
        let model = ReviewWindowModel(request: makeRequest(), loader: loader)

        let load = Task { await model.loadSelectedFile() }
        try await Task.sleep(for: .milliseconds(20))
        load.cancel()
        await load.value

        #expect(model.state(for: 0) == .notRequested)
        #expect(model.selectedFileID == "Sources/Zeta.swift")
        #expect(model.loadingIndex == nil)
    }

    @Test("Failures are visible and Retry can recover")
    func failureAndRetry() async throws {
        var attempts = 0
        let loader = MockReviewDiffLoader { index in
            attempts += 1
            if attempts == 1 {
                throw ReviewTestError.expired
            }
            return makeDetail(path: "Sources/Zeta.swift")
        }
        let model = ReviewWindowModel(request: makeRequest(), loader: loader)

        await model.loadSelectedFile()
        guard case let .failed(message) = model.state(for: 0) else {
            Issue.record("Expected a visible failure")
            return
        }
        #expect(message.contains("no longer available"))

        await model.loadSelectedFile(force: true)
        guard case .loaded = model.state(for: 0) else {
            Issue.record("Expected Retry to recover")
            return
        }
        #expect(attempts == 2)
    }

    @Test("A Host-unavailable comparison is loaded, not treated as a request failure")
    func unavailableIsADataState() async throws {
        let loader = MockReviewDiffLoader { _ in
            makeDetail(path: "Sources/Zeta.swift", kind: "unavailable", hunks: nil)
        }
        let model = ReviewWindowModel(request: makeRequest(), loader: loader)

        await model.loadSelectedFile()

        guard case let .loaded(file) = model.state(for: 0) else {
            Issue.record("Expected a loaded unavailable comparison")
            return
        }
        #expect(file.state == .unavailable)
        #expect(model.loadErrors.isEmpty)
    }

    @Test("Binary and oversized states remain accurate")
    func binaryAndOversizedStates() async throws {
        let binaryLoader = MockReviewDiffLoader { _ in
            makeDetail(path: "Sources/Zeta.swift", kind: "binary", hunks: nil)
        }
        let binaryModel = ReviewWindowModel(request: makeRequest(), loader: binaryLoader)
        await binaryModel.loadSelectedFile()
        guard case let .loaded(binary) = binaryModel.state(for: 0) else {
            Issue.record("Expected a loaded binary file")
            return
        }
        #expect(binary.state == .binary)

        let oversizedLoader = MockReviewDiffLoader { _ in
            makeDetail(path: "Sources/Zeta.swift", kind: "oversized", hunks: nil)
        }
        let oversizedModel = ReviewWindowModel(request: makeRequest(), loader: oversizedLoader)
        await oversizedModel.loadSelectedFile()
        guard case let .loaded(oversized) = oversizedModel.state(for: 0) else {
            Issue.record("Expected a loaded oversized file")
            return
        }
        #expect(oversized.state == .oversized)
    }

    @Test("Two Review windows keep independent identity and state")
    func independentWindows() async throws {
        let firstLoader = MockReviewDiffLoader { _ in
            makeDetail(path: "Sources/Zeta.swift")
        }
        let secondLoader = MockReviewDiffLoader { _ in
            makeDetail(path: "Sources/Alpha.swift")
        }
        let first = ReviewWindowModel(
            request: makeRequest(sessionID: "session-a", sequence: 1),
            loader: firstLoader
        )
        let second = ReviewWindowModel(
            request: makeRequest(sessionID: "session-b", sequence: 2),
            initialFileID: "Sources/Alpha.swift",
            loader: secondLoader
        )

        await first.loadSelectedFile()
        await second.loadSelectedFile()

        #expect(firstLoader.requests == [.init(sessionID: "session-a", sequence: 1, index: 0)])
        #expect(secondLoader.requests == [.init(sessionID: "session-b", sequence: 2, index: 1)])
        #expect(first.identity != second.identity)
        guard case let .loaded(firstFile) = first.state(for: 0),
              case let .loaded(secondFile) = second.state(for: 1) else {
            Issue.record("Expected both windows to load independently")
            return
        }
        #expect(firstFile.path == "Sources/Zeta.swift")
        #expect(secondFile.path == "Sources/Alpha.swift")
    }

    @Test("Releasing window resources drops loaded comparisons")
    func releaseResources() async {
        let loader = MockReviewDiffLoader { _ in
            makeDetail(path: "Sources/Zeta.swift")
        }
        let model = ReviewWindowModel(request: makeRequest(), loader: loader)
        await model.loadSelectedFile()
        #expect(model.loadedFiles.count == 1)

        model.releaseResources()

        #expect(model.loadedFiles.isEmpty)
        #expect(model.state(for: 0) == .notRequested)
    }
}

@Suite("Conversation changes placement")
@MainActor
struct ConversationChangesPlacementTests {
    private func item(_ sequence: Int) -> ChatItem {
        ChatItem(
            id: "item-\(sequence)",
            seq: sequence,
            time: Date(timeIntervalSince1970: Double(sequence)),
            kind: .notice(text: "Item \(sequence)")
        )
    }

    @Test("Session A changes are never visible in Session B")
    func sessionIsolation() {
        let context = WorkspaceChangesContext(
            sessionID: "session-a",
            sequence: 4,
            summary: makeSummary()
        )

        #expect(ConversationChangesPlacement.visibleContext(context, sessionID: "session-a") == context)
        #expect(ConversationChangesPlacement.visibleContext(context, sessionID: "session-b") == nil)
        #expect(ConversationChangesPlacement.visibleContext(context, sessionID: nil) == nil)
    }

    @Test("The summary is anchored at the workspace-changes event sequence")
    func anchoredPlacement() {
        let items = [1, 2, 3, 4, 5].map(item)

        let anchored = ConversationChangesPlacement.split(items, at: 4)

        #expect(anchored.before.map(\.seq) == [1, 2, 3])
        #expect(anchored.after.map(\.seq) == [4, 5])
    }

    @Test("Without a captured sequence all items remain in the normal transcript")
    func noAnchor() {
        let items = [1, 2, 3].map(item)

        let split = ConversationChangesPlacement.split(items, at: nil)

        #expect(split.before.map(\.seq) == [1, 2, 3])
        #expect(split.after.isEmpty)
    }
}

@Suite("AppModel review loading")
@MainActor
struct AppModelReviewLoadingTests {
    @Test("Comparison loading uses the supplied Session, not the global selection")
    func contextExplicitBridgeRequest() async throws {
        let bridge = MockBridgeService { method, _ in
            guard method == "workspace.changesDiff" else { return .object([:]) }
            return .object([
                "kind": .string("text"),
                "path": .string("Sources/Zeta.swift"),
                "display": .string("Zeta.swift"),
                "before": .bool(true),
                "after": .bool(true),
                "hunks": .array([]),
                "coarse": .bool(false)
            ])
        }
        let model = AppModel(bridge: bridge)
        model.selectedSessionID = "session-b"

        let diff = try await model.loadChangesDiff(
            sessionID: "session-a",
            sequence: 42,
            index: 3
        )

        #expect(diff.path == "Sources/Zeta.swift")
        let requests = await bridge.recordedRequests()
        let call = try #require(requests.last)
        #expect(call.method == "workspace.changesDiff")
        #expect(call.params["sessionId"]?.stringValue == "session-a")
        #expect(call.params["seq"]?.intValue == 42)
        #expect(call.params["index"]?.intValue == 3)
    }

    @Test("Registering a Review snapshots the Session title and change sequence")
    func registerReviewSnapshot() {
        let model = AppModel(bridge: MockBridgeService())
        let summary = makeSummary()
        model.sessions = [
            SessionSummary(
                sessionId: "session-a",
                updatedAt: nil,
                running: false,
                blank: false,
                cwd: "/Users/example/Project",
                agentAvailable: true,
                formatStatus: "current",
                parentSessionId: nil,
                origin: nil,
                projections: ProjectionHints(
                    kind: "sequenced",
                    asOfSeq: 42,
                    values: ["title": .string("Fix the Diff")]
                )
            )
        ]
        let context = WorkspaceChangesContext(
            sessionID: "session-a",
            sequence: 42,
            summary: summary
        )

        let identity = model.registerReview(for: context, selecting: "Sources/Alpha.swift")

        #expect(identity.sessionID == "session-a")
        #expect(identity.sequence == 42)
        #expect(identity.turn == 6)
        #expect(model.reviewCoordinator.request(for: identity)?.sessionTitle == "Fix the Diff")
        #expect(model.reviewCoordinator.selection(for: identity) == "Sources/Alpha.swift")
    }

    @Test("Changing the main Session clears the current changes context")
    func sessionSwitchClearsChanges() {
        let model = AppModel(bridge: MockBridgeService())
        model.changesContext = WorkspaceChangesContext(
            sessionID: "session-a",
            sequence: 42,
            summary: makeSummary()
        )

        model.selectSession("session-b")

        #expect(model.selectedSessionID == "session-b")
        #expect(model.changesContext == nil)
    }
}
