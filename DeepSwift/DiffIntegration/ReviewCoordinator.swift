//
//  ReviewCoordinator.swift
//  DeepSwift
//

import DiffUI
import Foundation
import Observation

/// Application-level routing for independent Review windows.
///
/// The coordinator stores one immutable request per Session/sequence and the
/// latest navigation intent. Window-local Diff data, loading state, and
/// presentation mode remain owned by each Review window.
@MainActor
@Observable
final class ReviewCoordinator {
    struct Request: Identifiable, Hashable, Sendable {
        let identity: ReviewIdentity
        let summary: WorkspaceChangesSummary
        let sessionTitle: String?

        var id: ReviewIdentity { identity }
    }

    private(set) var requests: [ReviewIdentity: Request] = [:]
    private var selections: [ReviewIdentity: String] = [:]
    private var selectionRevisions: [ReviewIdentity: Int] = [:]
    private var presentationModes: [ReviewIdentity: DiffPresentationMode] = [:]

    @discardableResult
    func register(
        sessionID: String,
        sequence: Int,
        turn: Int?,
        summary: WorkspaceChangesSummary,
        sessionTitle: String?,
        selecting fileID: String? = nil
    ) -> ReviewIdentity {
        let identity = ReviewIdentity(sessionID: sessionID, sequence: sequence, turn: turn)
        if requests[identity] == nil {
            requests[identity] = Request(
                identity: identity,
                summary: summary,
                sessionTitle: sessionTitle
            )
        }

        // The first request owns the immutable summary snapshot. Later
        // activation of the same Review only changes navigation intent.
        let captured = requests[identity]?.summary ?? summary
        if let fileID, captured.files.contains(where: { $0.path == fileID }) {
            setSelection(fileID, for: identity)
        } else if selections[identity] == nil {
            // The initial selection is part of the captured request, not a
            // navigation event. Window models read it when they are created.
            selections[identity] = captured.files.first?.path
        }
        return identity
    }

    func request(for identity: ReviewIdentity) -> Request? {
        requests[identity]
    }

    func selection(for identity: ReviewIdentity) -> String? {
        selections[identity]
    }

    func selectionRevision(for identity: ReviewIdentity) -> Int {
        selectionRevisions[identity] ?? 0
    }

    func setSelection(_ fileID: String?, for identity: ReviewIdentity) {
        if let fileID,
           let request = requests[identity],
           !request.summary.files.contains(where: { $0.path == fileID }) {
            return
        }
        guard selections[identity] != fileID else { return }
        selections[identity] = fileID
        selectionRevisions[identity, default: 0] += 1
    }

    func mode(for identity: ReviewIdentity) -> DiffPresentationMode {
        presentationModes[identity] ?? .unified
    }

    func setMode(_ mode: DiffPresentationMode, for identity: ReviewIdentity) {
        presentationModes[identity] = mode
    }

    /// Releases the captured request when its last window closes. Each window
    /// also releases its own loaded comparisons.
    func release(_ identity: ReviewIdentity) {
        requests.removeValue(forKey: identity)
        selections.removeValue(forKey: identity)
        selectionRevisions.removeValue(forKey: identity)
        presentationModes.removeValue(forKey: identity)
    }
}
