//
//  ReviewWindowModel.swift
//  DeepSwift
//

import DiffCore
import DiffUI
import Foundation
import Observation

@MainActor
protocol ReviewDiffLoading: AnyObject {
    func loadChangesDiff(
        sessionID: String,
        sequence: Int,
        index: Int
    ) async throws -> WorkspaceFileDiff
}

/// Per-window review state. It captures the Session/sequence and summary when
/// the window opens and never reads the application's mutable Session
/// selection afterwards.
@MainActor
@Observable
final class ReviewWindowModel {
    enum FileState: Equatable {
        case notRequested
        case loading
        case loaded(DiffFile)
        case failed(String)
    }

    let identity: ReviewIdentity
    let request: ReviewCoordinator.Request
    let summary: DiffChangeSummary
    var selectedFileID: String?
    var mode: DiffPresentationMode

    private(set) var loadingIndex: Int?
    private(set) var loadedFiles: [Int: DiffFile] = [:]
    private(set) var loadErrors: [Int: String] = [:]

    private let loader: any ReviewDiffLoading
    private var loadGeneration = 0

    init(
        request: ReviewCoordinator.Request,
        initialFileID: String? = nil,
        mode: DiffPresentationMode = .unified,
        loader: any ReviewDiffLoading
    ) {
        self.identity = request.identity
        self.request = request
        self.summary = DiffModelAdapter.changeSummary(
            from: request.summary,
            reviewID: request.identity
        )
        self.loader = loader
        self.mode = mode

        let validInitial = initialFileID.flatMap { fileID in
            request.summary.files.contains(where: { $0.path == fileID }) ? fileID : nil
        }
        selectedFileID = validInitial ?? request.summary.files.first?.path
    }

    var selectedFileIndex: Int? {
        guard let selectedFileID else { return nil }
        return request.summary.files.firstIndex(where: { $0.path == selectedFileID })
    }

    var fileCountText: String {
        summary.total == 1 ? "1 changed file" : "\(summary.total) changed files"
    }

    var sessionTitle: String {
        request.sessionTitle ?? "Session \(identity.sessionID.suffix(6))"
    }

    func state(for index: Int) -> FileState {
        if loadingIndex == index { return .loading }
        if let error = loadErrors[index] { return .failed(error) }
        if let file = loadedFiles[index] { return .loaded(file) }
        return .notRequested
    }

    func selectFile(_ fileID: String?) {
        guard let fileID,
              request.summary.files.contains(where: { $0.path == fileID }) else { return }
        guard selectedFileID != fileID else { return }
        selectedFileID = fileID
    }

    func selectAdjacentFile(offset: Int) {
        guard !request.summary.files.isEmpty else { return }
        let current = selectedFileIndex ?? 0
        let next = min(max(0, current + offset), request.summary.files.count - 1)
        selectedFileID = request.summary.files[next].path
    }

    /// Loads the selected comparison if it is not already cached. The view
    /// calls this from `.task(id:)`, so a selection change cancels the previous
    /// request; the generation guard also protects callers that complete out of
    /// order.
    func loadSelectedFile(force: Bool = false) async {
        guard let index = selectedFileIndex,
              request.summary.files.indices.contains(index) else { return }

        if !force {
            if loadedFiles[index] != nil { return }
            if loadingIndex == index { return }
        }

        let summaryFile = request.summary.files[index]
        loadGeneration += 1
        let generation = loadGeneration
        loadingIndex = index
        loadErrors[index] = nil

        defer {
            if loadGeneration == generation {
                loadingIndex = nil
            }
        }

        do {
            let detail = try await loader.loadChangesDiff(
                sessionID: identity.sessionID,
                sequence: identity.sequence,
                index: index
            )
            try Task.checkCancellation()
            guard loadGeneration == generation, selectedFileIndex == index else { return }
            loadedFiles[index] = try DiffModelAdapter.file(
                from: detail,
                summaryFile: summaryFile
            )
        } catch is CancellationError {
            return
        } catch {
            guard loadGeneration == generation, selectedFileIndex == index else { return }
            loadErrors[index] = error.localizedDescription
        }
    }

    func cancelLoading() {
        loadGeneration += 1
        loadingIndex = nil
    }

    func releaseResources() {
        cancelLoading()
        loadedFiles.removeAll()
        loadErrors.removeAll()
    }
}

extension AppModel: ReviewDiffLoading {}
