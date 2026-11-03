//
//  AppModel.swift
//  DeepSwift
//

import AppKit
import Foundation
import Observation
import OSLog

/// Native application state projected from the official DSH Host.
///
/// The model owns no DSH business rules: it forwards commands through the
/// bridge and folds authoritative events into view-facing state.
@MainActor
@Observable
final class AppModel {
    enum ConnectionState: Equatable {
        case idle
        case starting
        case ready
        case degraded(String)
        case failed(String)

        var isReady: Bool {
            if case .ready = self { return true }
            return false
        }

        var label: String {
            switch self {
            case .idle: return "Not connected"
            case .starting: return "Starting runtime…"
            case .ready: return "Connected"
            case let .degraded(message): return message
            case let .failed(message): return message
            }
        }
    }

    struct PendingPrompt: Identifiable, Hashable, Sendable {
        let id: String
        let text: String
        let date: Date
        let attachmentNames: [String]
    }

    var connectionState: ConnectionState = .idle
    var runtimeFacts: RuntimeFacts?
    var runtimeConfiguration: RuntimeConfiguration?
    var workspaces: [WorkspaceItem] = []
    var sessions: [SessionSummary] = []
    var archivedSessionIDs: [String] = []
    var pinnedSessionIDs: [String] = []
    var selectedWorkspaceID: String?
    var selectedSessionID: String?
    var conversation = ConversationProjection()
    var conversationSessionID: String?
    var isLoadingConversation = false
    var isLoadingOlder = false
    var isSending = false
    var draft = ""
    var attachments: [ComposerAttachment] = []
    var searchText = ""
    var models: ModelCatalog?
    var commands: [CommandDescriptor] = []
    var account: AccountView?
    var isSigningIn = false
    var pendingApprovals: [PendingApproval] = []
    var pendingQuestions: [PendingQuestion] = []
    var pendingPrompts: [PendingPrompt] = []
    var errorMessage: String?
    var diagnosticLog = ""
    var showInspector = false
    var showFiles = false
    var showSearch = false
    var searchQuery = ""
    var searchResults: [SessionSearchHit] = []
    var isSearchingMessages = false
    var filesPath = ""
    var fileListing: WorkspaceDirectoryListing?
    var filePreview: WorkspaceFileText?
    var filePreviewPath: String?
    var filePreviewError: String?
    var isLoadingFiles = false
    var jobs: [BackgroundJob] = []
    var lastRuntimeError: String?

    private let bridge: any DSHBridgeService
    private let logger = Logger(subsystem: "com.lloydME.DeepSwift", category: "AppModel")
    private var notificationTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var followGeneration = 0
    private var followStreamID: String?
    private var jobsStreamID: String?
    private var eventStreamsOpened = false
    private var didBootstrap = false
    private var lastConnectedClientID: String?
    private var accountPollTask: Task<Void, Never>?
    private var followAddress: JSONValue = .object(["kind": .string("session")])
    private var openedSignInAttemptID: String?

    init(bridge: any DSHBridgeService = BridgeClient()) {
        self.bridge = bridge
    }

    // MARK: - Lifecycle

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        listen()
        connectionState = .starting
        do {
            let configuration = try RuntimeConfiguration.resolve()
            runtimeConfiguration = configuration
            logger.info("Launching bridge with isolated home \(configuration.dshHome, privacy: .public)")
            try await bridge.start(configuration: configuration)
            let factsValue = try await bridge.request("runtime.start", timeout: .seconds(60))
            runtimeFacts = try? factsValue.decode(RuntimeFacts.self)
            connectionState = .ready
            logger.info("Runtime started: \(self.runtimeFacts?.dshVersion ?? "unknown", privacy: .public)")
            await openInitialStreams()
            await refreshSessions()
            await refreshModels()
            await refreshAccount()
        } catch {
            logger.error("Bootstrap failed: \(error.localizedDescription, privacy: .public)")
            connectionState = .failed(error.localizedDescription)
            lastRuntimeError = error.localizedDescription
        }
    }

    func shutdown() async {
        notificationTask?.cancel()
        refreshTask?.cancel()
        accountPollTask?.cancel()
        await bridge.stop()
    }

    private func listen() {
        notificationTask = Task { [weak self] in
            guard let self else { return }
            for await notification in self.bridge.notifications {
                self.handle(notification)
            }
        }
    }

    private func handle(_ notification: BridgeNotification) {
        switch notification.event {
        case "bridge.hello":
            if let logPath = notification.data["logPath"]?.stringValue {
                diagnosticLog = logPath
            }
        case "runtime.starting":
            connectionState = .starting
        case "runtime.ready":
            runtimeFacts = try? notification.data.decode(RuntimeFacts.self)
            connectionState = .ready
            lastRuntimeError = nil
            logger.info("Runtime ready event")
            Task { await openInitialStreams() }
        case "host.connected":
            connectionState = .ready
            lastRuntimeError = nil
            logger.info("Host event stream connected")
            let clientID = notification.data["clientId"]?.stringValue
            if clientID != lastConnectedClientID {
                lastConnectedClientID = clientID
                eventStreamsOpened = false
                Task { await openInitialStreams() }
                scheduleSessionRefresh()
            }
        case "host.reconnected":
            connectionState = .ready
            runtimeFacts = try? notification.data.decode(RuntimeFacts.self)
            scheduleSessionRefresh()
        case "host.disconnected":
            logger.warning("Host event stream disconnected")
            connectionState = .degraded("Reconnecting to the runtime…")
        case "host.reconnecting":
            connectionState = .degraded("Reconnecting to the runtime…")
        case "host.eventStreamFailed":
            diagnosticLog = notification.data["message"]?.stringValue ?? diagnosticLog
        case "runtime.failed":
            let message = notification.data["message"]?.stringValue ?? "The DSH runtime failed to start."
            let stderr = notification.data["stderr"]?.stringValue ?? ""
            lastRuntimeError = stderr.isEmpty ? message : "\(message)\n\n\(stderr)"
            connectionState = .failed(message)
            errorMessage = message
        case "runtime.exited":
            let code = notification.data["code"]?.intValue ?? -1
            connectionState = .failed("The DSH runtime exited unexpectedly (code \(code)).")
        case "bridge.exited":
            connectionState = .failed("The local bridge exited.")
        case "bridge.log":
            if let line = notification.data.stringValue, line.contains("error") {
                diagnosticLog = String((diagnosticLog + line).suffix(20_000))
            }
        case "bridge.malformed", "bridge.protocolError", "bridge.failed":
            errorMessage = notification.data["message"]?.stringValue ?? notification.data.stringValue
        case "stream.item":
            handleStreamItem(notification.data)
        case "stream.reset":
            handleStreamReset(notification.data)
        case "stream.error":
            handleStreamError(notification.data)
        case "stream.end":
            if let id = notification.data["id"]?.stringValue, id == followStreamID {
                isLoadingConversation = false
            }
        case "host.event":
            handleHostEvent(name: notification.data["event"]?.stringValue ?? "", args: notification.data["args"]?.arrayValue ?? [])
        case "approval.request":
            if let approval = try? notification.data.decode(PendingApproval.self),
               !pendingApprovals.contains(where: { $0.eventId == approval.eventId }) {
                pendingApprovals.append(approval)
            }
        case "approval.cancelled":
            if let eventID = notification.data["eventId"]?.stringValue {
                pendingApprovals.removeAll { $0.eventId == eventID }
            }
        case "question.request":
            if let question = try? notification.data.decode(PendingQuestion.self),
               !pendingQuestions.contains(where: { $0.eventId == question.eventId }) {
                pendingQuestions.append(question)
            }
        case "question.cancelled":
            if let eventID = notification.data["eventId"]?.stringValue {
                pendingQuestions.removeAll { $0.eventId == eventID }
            }
        default:
            break
        }
    }

    // MARK: - Streams

    private func openInitialStreams() async {
        guard !eventStreamsOpened else { return }
        eventStreamsOpened = true
        do {
            _ = try await bridge.request("stream.open", params: .object([
                "id": .string("workspaces"),
                "endpoint": .string("workspace/follow"),
                "args": .object([:])
            ]))
            _ = try await bridge.request("stream.open", params: .object([
                "id": .string("control"),
                "endpoint": .string("session/control"),
                "args": .object([:])
            ]))
        } catch let error as BridgeClientError {
            switch error.code {
            case "stream/duplicate":
                break
            default:
                eventStreamsOpened = false
                errorMessage = error.localizedDescription
            }
        } catch {
            eventStreamsOpened = false
            errorMessage = error.localizedDescription
        }
    }

    private func handleStreamItem(_ data: JSONValue) {
        guard let id = data["id"]?.stringValue, let value = data["value"] else { return }
        switch id {
        case "workspaces":
            applyWorkspaceFrame(value)
        case "control":
            applyControlFrame(value)
        case let streamID where streamID == followStreamID:
            applyFollowFrame(value)
        case let streamID where streamID == jobsStreamID:
            if let jobs = value["jobs"]?.arrayValue {
                self.jobs = jobs.compactMap { try? $0.decode(BackgroundJob.self) }
            }
        default:
            break
        }
    }

    private func handleStreamReset(_ data: JSONValue) {
        guard let id = data["id"]?.stringValue else { return }
        if id == followStreamID {
            isLoadingConversation = true
            diagnosticLog = "Session stream reset: \(data["reason"]?.stringValue ?? "carrier reset")"
        } else if id == jobsStreamID {
            jobs = []
        } else if id == "workspaces" {
            workspaces = []
        }
    }

    private func handleStreamError(_ data: JSONValue) {
        guard let id = data["id"]?.stringValue else { return }
        let message = data["message"]?.stringValue ?? "Remote stream failed."
        if id == followStreamID {
            isLoadingConversation = false
            errorMessage = message
        } else if id == jobsStreamID {
            diagnosticLog = "Job stream ended: \(message)"
        } else {
            diagnosticLog = "\(notificationPrefix(id)) \(message)"
        }
    }

    private func notificationPrefix(_ id: String) -> String {
        "[\(id)]"
    }

    // MARK: - Workspace and session state

    private func applyWorkspaceFrame(_ frame: JSONValue) {
        guard let type = frame["type"]?.stringValue else { return }
        switch type {
        case "baseline":
            let value = frame["value"]
            workspaces = (value?["items"]?.arrayValue ?? []).compactMap { try? $0.decode(WorkspaceItem.self) }
            logger.info("Workspace baseline: \(self.workspaces.count, privacy: .public)")
            archivedSessionIDs = value?["archivedSessionIds"]?.arrayValue?.compactMap(\.stringValue) ?? []
            pinnedSessionIDs = value?["pinnedSessionIds"]?.arrayValue?.compactMap(\.stringValue) ?? []
            chooseInitialWorkspace()
        case "upsert":
            guard let workspace = frame["workspace"].flatMap({ try? $0.decode(WorkspaceItem.self) }) else { return }
            if let index = workspaces.firstIndex(where: { $0.workspaceId == workspace.workspaceId }) {
                workspaces[index] = workspace
            } else {
                workspaces.append(workspace)
            }
            chooseInitialWorkspace()
        case "remove":
            guard let workspaceID = frame["workspaceId"]?.stringValue else { return }
            workspaces.removeAll { $0.workspaceId == workspaceID }
            if selectedWorkspaceID == workspaceID { selectedWorkspaceID = workspaces.first?.workspaceId }
        case "order":
            let ids = frame["workspaceIds"]?.arrayValue?.compactMap(\.stringValue) ?? []
            workspaces.sort { lhs, rhs in
                (ids.firstIndex(of: lhs.workspaceId) ?? .max) < (ids.firstIndex(of: rhs.workspaceId) ?? .max)
            }
        case "archived":
            archivedSessionIDs = frame["archivedSessionIds"]?.arrayValue?.compactMap(\.stringValue) ?? []
            if let selectedSessionID, archivedSessionIDs.contains(selectedSessionID) {
                selectSession(nil)
            }
        case "pinned":
            pinnedSessionIDs = frame["pinnedSessionIds"]?.arrayValue?.compactMap(\.stringValue) ?? []
        case "replace":
            applyWorkspaceFrame(.object(["type": .string("baseline"), "value": frame["value"] ?? .object([:])]))
        default:
            break
        }
    }

    private func chooseInitialWorkspace() {
        let saved = UserDefaults.standard.string(forKey: "selectedWorkspaceID")
        if selectedWorkspaceID == nil {
            if let saved, workspaces.contains(where: { $0.workspaceId == saved }) {
                selectedWorkspaceID = saved
            } else {
                selectedWorkspaceID = workspaces.first?.workspaceId
            }
        }
        if selectedSessionID == nil {
            let savedSession = UserDefaults.standard.string(forKey: "selectedSessionID")
            if let savedSession, sessions.contains(where: { $0.sessionId == savedSession }) {
                selectSession(savedSession)
            } else {
                let candidates = selectedWorkspace.map { sessions(in: $0) } ?? visibleSessions
                if let first = candidates.first {
                    selectSession(first.sessionId)
                }
            }
        }
    }

    private func applyControlFrame(_ frame: JSONValue) {
        guard let type = frame["type"]?.stringValue else { return }
        switch type {
        case "baseline":
            let projections = frame["value"]?["projections"]?.objectValue ?? [:]
            for (sessionID, baseline) in projections {
                guard let values = baseline["values"]?["title"] else { continue }
                if let title = values.stringValue, let index = sessions.firstIndex(where: { $0.sessionId == sessionID }) {
                    sessions[index] = sessions[index].replacingTitle(title)
                }
            }
        case "projection":
            guard let sessionID = frame["sessionId"]?.stringValue,
                  frame["key"]?.stringValue == "title" else { return }
            if let title = frame["value"]?.stringValue,
               let index = sessions.firstIndex(where: { $0.sessionId == sessionID }) {
                sessions[index] = sessions[index].replacingTitle(title)
            }
        default:
            break
        }
    }

    private func applyFollowFrame(_ frame: JSONValue) {
        switch frame["type"]?.stringValue {
        case "snapshot":
            conversation.apply(snapshot: frame)
            isLoadingConversation = false
            logger.info("Conversation snapshot: \(self.conversation.items.count, privacy: .public) items, more=\(self.conversation.hasMore, privacy: .public)")
            if let title = conversation.title, let id = conversationSessionID,
               let index = sessions.firstIndex(where: { $0.sessionId == id }) {
                sessions[index] = sessions[index].replacingTitle(title)
            }
        case "event":
            guard let eventValue = frame["event"], let event = SessionWireEvent(value: eventValue) else { return }
            conversation.apply(event: event)
            if event.type == "user/message" {
                settlePendingPrompt(source: event.data["message"]?["source"] ?? event.data["source"])
            }
            if event.type == "session/title", let title = event.data["title"]?.stringValue,
               let id = conversationSessionID,
               let index = sessions.firstIndex(where: { $0.sessionId == id }) {
                sessions[index] = sessions[index].replacingTitle(title)
            }
        case "assistant-stream":
            if let assistantFrame = frame["frame"] {
                conversation.apply(assistantFrame: assistantFrame)
            }
        default:
            break
        }
    }

    private func settlePendingPrompt(source: JSONValue?) {
        guard let requestID = source?["rpcId"]?.stringValue else { return }
        pendingPrompts.removeAll { $0.id == requestID }
    }

    // MARK: - Loading

    func refreshSessions() async {
        guard connectionState.isReady else { return }
        do {
            let result = try await bridge.request("host.call", params: .object([
                "namespace": .string("session"),
                "method": .string("list"),
                "args": .object(["_request": .object([:])])
            ]))
            let items = result["items"]?.arrayValue ?? []
            var decoded = items.compactMap { try? $0.decode(SessionSummary.self) }
            // Preserve a live running bit when a list snapshot arrives mid-stream.
            for index in decoded.indices {
                if let current = sessions.first(where: { $0.sessionId == decoded[index].sessionId }),
                   decoded[index].running == nil {
                    decoded[index] = decoded[index].replacingRunning(current.running)
                }
            }
            sessions = decoded.sorted { ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) }
            logger.info("Loaded \(self.sessions.count, privacy: .public) sessions")
            if let selectedSessionID, !sessions.contains(where: { $0.sessionId == selectedSessionID }) {
                selectSession(nil)
            }
            chooseInitialWorkspace()
        } catch {
            diagnosticLog = "Session list failed: \(error.localizedDescription)"
        }
    }

    func refreshCommands() async {
        guard let sessionID = selectedSessionID else {
            commands = []
            return
        }
        do {
            let result = try await bridge.request("host.call", params: .object([
                "namespace": .string("commands"),
                "method": .string("list"),
                "args": .object(["agentId": .string(sessionID)])
            ]), timeout: .seconds(20))
            commands = (result.arrayValue ?? []).compactMap { try? $0.decode(CommandDescriptor.self) }
        } catch {
            commands = []
            diagnosticLog = "Commands unavailable: \(error.localizedDescription)"
        }
    }

    var commandSuggestions: [CommandDescriptor] {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/"), !trimmed.dropFirst().contains(" ") else { return [] }
        return commands
            .filter { $0.slashName.hasPrefix(trimmed) }
            .prefix(5)
            .map { $0 }
    }

    func applyCommandSuggestion(_ command: CommandDescriptor) {
        draft = command.slashName + " "
    }

    private func executeCommand(_ line: String, sessionID: String) async throws -> Bool {
        let result = try await bridge.request("host.call", params: .object([
            "namespace": .string("commands"),
            "method": .string("execute"),
            "args": .object([
                "agentId": .string(sessionID),
                "line": .string(line),
                "submittedAttachments": .array([])
            ])
        ]), timeout: .seconds(30))
        // `undefined`/null means the line is not a recognized command; the
        // caller falls back to the ordinary prompt path.
        return result.objectValue != nil
    }

    func refreshModels() async {
        guard connectionState.isReady else { return }
        do {
            let result = try await bridge.request("host.call", params: .object([
                "namespace": .string("session"),
                "method": .string("modelCatalog"),
                "args": .object([:])
            ]))
            models = try? result.decode(ModelCatalog.self)
        } catch {
            diagnosticLog = "Model catalog unavailable: \(error.localizedDescription)"
        }
    }

    func refreshAccount() async {
        guard connectionState.isReady else { return }
        do {
            let result = try await bridge.request("account.state", timeout: .seconds(15))
            account = try? result.decode(AccountView.self)
        } catch {
            diagnosticLog = "Account state unavailable: \(error.localizedDescription)"
        }
    }

    func beginSignIn() async {
        guard connectionState.isReady, !isSigningIn else { return }
        isSigningIn = true
        errorMessage = nil
        openedSignInAttemptID = nil
        accountPollTask?.cancel()
        do {
            let result = try await bridge.request("account.signIn", timeout: .seconds(30))
            let view = try? result.decode(AccountView.self)
            account = view
            openAuthorizeURLIfNeeded()
            startAccountPolling()
        } catch {
            isSigningIn = false
            errorMessage = "Sign-in could not start: \(error.localizedDescription)"
        }
    }

    func cancelSignIn() async {
        guard let attempt = account?.attempt else {
            isSigningIn = false
            return
        }
        accountPollTask?.cancel()
        openedSignInAttemptID = nil
        do {
            let result = try await bridge.request("account.cancelSignIn", params: .object([
                "attemptId": .string(attempt.id)
            ]), timeout: .seconds(20))
            account = try? result.decode(AccountView.self)
        } catch {
            errorMessage = error.localizedDescription
        }
        isSigningIn = false
    }

    func signOut() async {
        do {
            let result = try await bridge.request("account.signOut", timeout: .seconds(30))
            account = try? result.decode(AccountView.self)
            openedSignInAttemptID = nil
            await refreshModels()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startAccountPolling() {
        accountPollTask?.cancel()
        accountPollTask = Task { [weak self] in
            for _ in 0..<150 {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                await self.refreshAccount()
                self.openAuthorizeURLIfNeeded()
                guard let attempt = self.account?.attempt else { continue }
                if self.account?.isSignedIn == true || attempt.phase == "succeeded" {
                    self.isSigningIn = false
                    await self.refreshModels()
                    return
                }
                if ["failed", "expired", "cancelled"].contains(attempt.phase) {
                    self.isSigningIn = false
                    if let code = attempt.errorCode {
                        self.errorMessage = "Sign-in failed: \(code)"
                    }
                    return
                }
            }
            self?.isSigningIn = false
        }
    }

    private func openAuthorizeURLIfNeeded() {
        guard let attempt = account?.attempt,
              let urlString = attempt.authorizeUrl,
              let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "https",
              openedSignInAttemptID != attempt.id else { return }
        openedSignInAttemptID = attempt.id
        NSWorkspace.shared.open(url)
    }

    func refreshRuntime() async {
        do {
            let result = try await bridge.request("runtime.status", timeout: .seconds(10))
            runtimeFacts = try? result.decode(RuntimeFacts.self)
        } catch {
            lastRuntimeError = error.localizedDescription
        }
    }

    private func scheduleSessionRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.refreshSessions()
        }
    }

    // MARK: - Selection

    func selectSubagent(_ session: SessionSummary) {
        guard let parent = session.parentSessionId else { return }
        if let workspace = workspace(for: session) {
            selectWorkspace(workspace.workspaceId)
        }
        selectSession(session.sessionId, subagentOf: parent)
    }

    func selectWorkspace(_ id: String?) {
        selectedWorkspaceID = id
        UserDefaults.standard.set(id, forKey: "selectedWorkspaceID")
    }

    func selectSession(_ id: String?, subagentOf parent: String? = nil) {
        guard selectedSessionID != id || id == nil || followStreamID == nil || parent != nil else { return }
        let previous = followStreamID
        let previousJobs = jobsStreamID
        selectedSessionID = id
        conversationSessionID = id
        conversation.reset()
        pendingPrompts = []
        attachments = []
        jobs = []
        errorMessage = nil
        filesPath = ""
        fileListing = nil
        filePreview = nil
        filePreviewPath = nil
        filePreviewError = nil
        UserDefaults.standard.set(id, forKey: "selectedSessionID")
        followGeneration += 1
        let generation = followGeneration
        followStreamID = id == nil ? nil : "follow-\(generation)"
        jobsStreamID = id == nil || parent != nil ? nil : "jobs-\(generation)"
        if let id {
            if let parent {
                followAddress = .object([
                    "kind": .string("subagent"),
                    "parentSessionId": .string(parent),
                    "childSessionId": .string(id),
                    "mode": .string("unknown")
                ])
            } else {
                followAddress = .object(["kind": .string("session"), "sessionId": .string(id)])
            }
        }
        for stream in [previous, previousJobs].compactMap({ $0 }) {
            Task { _ = try? await bridge.request("stream.close", params: .object(["id": .string(stream)])) }
        }
        guard let id else {
            isLoadingConversation = false
            return
        }
        isLoadingConversation = true
        let streamID = "follow-\(generation)"
        let jobsID = "jobs-\(generation)"
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self, self.selectedSessionID == id else { return }
            await self.refreshCommands()
        }
        if parent == nil {
            Task { [weak self] in
                guard let self, self.jobsStreamID == jobsID else { return }
                _ = try? await self.bridge.request("stream.open", params: .object([
                    "id": .string(jobsID),
                    "endpoint": .string("job/list"),
                    "args": .object(["request": .object(["sessionId": .string(id)])])
                ]))
            }
        }
        let address = followAddress
        Task { [weak self] in
            guard let self, self.followStreamID == streamID else { return }
            do {
                _ = try await self.bridge.request("stream.open", params: .object([
                    "id": .string(streamID),
                    "endpoint": .string("session/follow"),
                    "args": .object([
                        "request": .object([
                            "address": address,
                            "activate": .bool(false),
                            "assistantStream": .bool(true),
                            "maxMessages": .number(120),
                            "turnWindow": .object([
                                "minMessages": .number(60),
                                "minTurns": .number(2)
                            ])
                        ])
                    ])
                ]))
            } catch {
                if self.followStreamID == streamID {
                    self.isLoadingConversation = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    var selectedSession: SessionSummary? {
        guard let selectedSessionID else { return nil }
        return sessions.first { $0.sessionId == selectedSessionID }
    }

    var selectedWorkspace: WorkspaceItem? {
        guard let selectedWorkspaceID else { return nil }
        return workspaces.first { $0.workspaceId == selectedWorkspaceID }
    }

    var visibleSessions: [SessionSummary] {
        let archived = Set(archivedSessionIDs)
        let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return sessions.filter { session in
            guard !session.isSubagent, !archived.contains(session.sessionId) else { return false }
            guard !search.isEmpty else { return true }
            return session.displayTitle.localizedCaseInsensitiveContains(search)
                || (session.cwd?.localizedCaseInsensitiveContains(search) ?? false)
        }
    }

    func sessions(in workspace: WorkspaceItem) -> [SessionSummary] {
        let ids = Set(workspace.sessionIds)
        let archived = Set(archivedSessionIDs)
        return visibleSessions
            .filter { ids.contains($0.sessionId) && !archived.contains($0.sessionId) }
            .sorted { lhs, rhs in
                let lhsPinned = pinnedSessionIDs.contains(lhs.sessionId)
                let rhsPinned = pinnedSessionIDs.contains(rhs.sessionId)
                if lhsPinned != rhsPinned { return lhsPinned }
                return (lhs.updatedAt ?? 0) > (rhs.updatedAt ?? 0)
            }
    }

    func subagents(of session: SessionSummary?) -> [SessionSummary] {
        guard let session else { return [] }
        return sessions
            .filter { $0.parentSessionId == session.sessionId }
            .sorted { ($0.updatedAt ?? 0) < ($1.updatedAt ?? 0) }
    }

    var ungroupedSessions: [SessionSummary] {
        let known = Set(workspaces.flatMap(\.sessionIds))
        return visibleSessions.filter { !known.contains($0.sessionId) }
    }

    func workspace(for session: SessionSummary?) -> WorkspaceItem? {
        guard let session else { return nil }
        return workspaces.first { $0.sessionIds.contains(session.sessionId) }
    }

    // MARK: - Commands

    func createSession() async {
        guard let workspace = selectedWorkspace else {
            errorMessage = "Create or select a workspace before starting a session."
            return
        }
        do {
            let result = try await bridge.request("host.call", params: .object([
                "namespace": .string("session"),
                "method": .string("create"),
                "args": .object([
                    "request": .object(["workspaceId": .string(workspace.workspaceId)])
                ])
            ]))
            guard let sessionID = result["sessionId"]?.stringValue else {
                throw BridgeClientError.protocolViolation("Session creation returned no identity.")
            }
            await refreshSessions()
            selectSession(sessionID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createWorkspace() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Workspace Folder"
        panel.prompt = "Use Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                let result = try await bridge.request("host.call", params: .object([
                    "namespace": .string("workspace"),
                    "method": .string("create"),
                    "args": .object(["request": .object(["path": .string(url.path)])])
                ]))
                if let workspace = try? result["workspace"]?.decode(WorkspaceItem.self) {
                    if let index = workspaces.firstIndex(where: { $0.workspaceId == workspace.workspaceId }) {
                        workspaces[index] = workspace
                    } else {
                        workspaces.append(workspace)
                    }
                    selectWorkspace(workspace.workspaceId)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func renameWorkspace(_ workspace: WorkspaceItem, to title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let result = try await bridge.request("host.call", params: .object([
                "namespace": .string("workspace"),
                "method": .string("rename"),
                "args": .object([
                    "request": .object([
                        "workspaceId": .string(workspace.workspaceId),
                        "title": .string(trimmed)
                    ])
                ])
            ]))
            if let updated = try? result["workspace"]?.decode(WorkspaceItem.self),
               let index = workspaces.firstIndex(where: { $0.workspaceId == workspace.workspaceId }) {
                workspaces[index] = updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteWorkspace(_ workspace: WorkspaceItem) async {
        do {
            _ = try await bridge.request("host.call", params: .object([
                "namespace": .string("workspace"),
                "method": .string("delete"),
                "args": .object(["request": .object(["workspaceId": .string(workspace.workspaceId)])])
            ]))
            workspaces.removeAll { $0.workspaceId == workspace.workspaceId }
            if selectedWorkspaceID == workspace.workspaceId {
                selectedWorkspaceID = workspaces.first?.workspaceId
                selectSession(nil)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func renameSession(_ session: SessionSummary, to title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            _ = try await bridge.request("host.call", params: .object([
                "namespace": .string("session"),
                "method": .string("rename"),
                "args": .object([
                    "request": .object([
                        "sessionId": .string(session.sessionId),
                        "title": .string(trimmed)
                    ])
                ])
            ]))
            if let index = sessions.firstIndex(where: { $0.sessionId == session.sessionId }) {
                sessions[index] = sessions[index].replacingTitle(trimmed)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func archiveSession(_ session: SessionSummary) async {
        do {
            let result = try await bridge.request("host.call", params: .object([
                "namespace": .string("workspace"),
                "method": .string("archiveSession"),
                "args": .object([
                    "request": .object(["sessionId": .string(session.sessionId), "stopActivity": .bool(false)])
                ])
            ]))
            archivedSessionIDs = result["archivedSessionIds"]?.arrayValue?.compactMap(\.stringValue) ?? archivedSessionIDs
            if selectedSessionID == session.sessionId { selectSession(nil) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func pinSession(_ session: SessionSummary) async {
        do {
            let result = try await bridge.request("host.call", params: .object([
                "namespace": .string("workspace"),
                "method": .string("pinSession"),
                "args": .object(["request": .object(["sessionId": .string(session.sessionId)])])
            ]))
            pinnedSessionIDs = result["pinnedSessionIds"]?.arrayValue?.compactMap(\.stringValue) ?? pinnedSessionIDs
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func unpinSession(_ session: SessionSummary) async {
        do {
            let result = try await bridge.request("host.call", params: .object([
                "namespace": .string("workspace"),
                "method": .string("unpinSession"),
                "args": .object(["request": .object(["sessionId": .string(session.sessionId)])])
            ]))
            pinnedSessionIDs = result["pinnedSessionIds"]?.arrayValue?.compactMap(\.stringValue) ?? pinnedSessionIDs
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func unarchiveSession(_ sessionID: String) async {
        do {
            let result = try await bridge.request("host.call", params: .object([
                "namespace": .string("workspace"),
                "method": .string("unarchiveSession"),
                "args": .object(["request": .object(["sessionId": .string(sessionID)])])
            ]))
            archivedSessionIDs = result["archivedSessionIds"]?.arrayValue?.compactMap(\.stringValue) ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectModel(_ selection: ModelSelection) async {
        guard let sessionID = selectedSessionID else { return }
        do {
            var request: [String: JSONValue] = [
                "sessionId": .string(sessionID),
                "provider": .string(selection.provider),
                "model": .string(selection.model)
            ]
            if let effort = selection.reasoningEffort {
                request["reasoningEffort"] = .string(effort)
            }
            _ = try await bridge.request("host.call", params: .object([
                "namespace": .string("session"),
                "method": .string("selectModel"),
                "args": .object(["request": .object(request)])
            ]))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sendMessage() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!text.isEmpty || !attachments.isEmpty), let sessionID = selectedSessionID,
              selectedSession?.isSubagent != true, !isSending else { return }
        isSending = true
        let requestID = UUID().uuidString.lowercased()
        if attachments.isEmpty, text.hasPrefix("/") {
            do {
                if try await executeCommand(text, sessionID: sessionID) {
                    draft = ""
                    isSending = false
                    return
                }
            } catch {
                errorMessage = error.localizedDescription
                isSending = false
                return
            }
        }
        let sentAttachments = attachments
        var content: [JSONValue] = []
        if !text.isEmpty {
            content.append(.object(["type": .string("text"), "text": .string(text)]))
        }
        for attachment in sentAttachments {
            content.append(.object([
                "type": .string("image"),
                "data": .string(attachment.data.base64EncodedString()),
                "mediaType": .string(attachment.mimeType),
                "name": .string(attachment.name)
            ]))
        }
        do {
            _ = try await bridge.request("host.call", params: .object([
                "namespace": .string("session"),
                "method": .string("prompt"),
                "args": .object([
                    "request": .object([
                        "requestId": .string(requestID),
                        "sessionId": .string(sessionID),
                        "mode": .string("queue"),
                        "content": .array(content),
                        "clientTimeZone": .string(TimeZone.current.identifier)
                    ])
                ])
            ]), timeout: .seconds(90))
            pendingPrompts.append(PendingPrompt(
                id: requestID,
                text: text,
                date: Date(),
                attachmentNames: sentAttachments.map(\.name)
            ))
            draft = ""
            attachments = []
        } catch {
            errorMessage = error.localizedDescription
        }
        isSending = false
    }

    func attachImage(at url: URL) async {
        guard attachments.count < 8 else {
            errorMessage = "Up to eight images can be attached to one message."
            return
        }
        let supported: [String: String] = [
            "png": "image/png",
            "jpg": "image/jpeg",
            "jpeg": "image/jpeg",
            "gif": "image/gif",
            "webp": "image/webp"
        ]
        let ext = url.pathExtension.lowercased()
        guard let mimeType = supported[ext] else {
            errorMessage = "Only PNG, JPEG, GIF, and WebP images can be attached."
            return
        }
        do {
            let data = try await Task.detached(priority: .userInitiated) {
                try Data(contentsOf: url)
            }.value
            guard data.count <= 20 * 1024 * 1024 else {
                errorMessage = "Images must be 20 MB or smaller."
                return
            }
            attachments.append(ComposerAttachment(name: url.lastPathComponent, mimeType: mimeType, data: data))
        } catch {
            errorMessage = "Could not read \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func removeAttachment(_ attachment: ComposerAttachment) {
        attachments.removeAll { $0.id == attachment.id }
    }

    func cancelCurrentTurn() async {
        guard let sessionID = selectedSessionID else { return }
        do {
            _ = try await bridge.request("host.call", params: .object([
                "namespace": .string("session"),
                "method": .string("cancel"),
                "args": .object(["request": .object(["sessionId": .string(sessionID)])])
            ]))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func searchMessages() async {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        isSearchingMessages = true
        defer { isSearchingMessages = false }
        do {
            let result = try await bridge.request("host.call", params: .object([
                "namespace": .string("session"),
                "method": .string("search"),
                "args": .object(["request": .object(["query": .string(query)])])
            ]), timeout: .seconds(30))
            searchResults = (result["items"]?.arrayValue ?? []).compactMap { try? $0.decode(SessionSearchHit.self) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadFiles(path: String = "") async {
        guard let sessionID = selectedSessionID, !isLoadingFiles else { return }
        isLoadingFiles = true
        defer { isLoadingFiles = false }
        do {
            let result = try await bridge.request("host.call", params: .object([
                "namespace": .string("workspaceFiles"),
                "method": .string("list"),
                "args": .object([
                    "workspaceFileScopeId": .string(sessionID),
                    "path": .string(path.isEmpty ? "." : path)
                ])
            ]), timeout: .seconds(20))
            fileListing = try result.decode(WorkspaceDirectoryListing.self)
            filesPath = fileListing?.path ?? path
        } catch {
            filePreviewError = "Could not list the workspace: \(error.localizedDescription)"
        }
    }

    func openFile(_ entry: WorkspaceFileEntry) async {
        guard let sessionID = selectedSessionID else { return }
        let path = filesPath.isEmpty ? entry.name : "\(filesPath)/\(entry.name)"
        filePreviewError = nil
        do {
            let result = try await bridge.request("host.call", params: .object([
                "namespace": .string("workspaceFiles"),
                "method": .string("read"),
                "args": .object([
                    "workspaceFileScopeId": .string(sessionID),
                    "path": .string(path),
                    "range": .object(["offset": .number(1), "limit": .number(5_000)])
                ])
            ]), timeout: .seconds(20))
            filePreview = try result.decode(WorkspaceFileText.self)
            filePreviewPath = path
        } catch {
            filePreview = nil
            filePreviewPath = path
            filePreviewError = "This file cannot be shown as text. \(error.localizedDescription)"
        }
    }

    func loadFilesParent() async {
        guard !filesPath.isEmpty else { return }
        let parent = filesPath.split(separator: "/").dropLast().joined(separator: "/")
        await loadFiles(path: parent)
    }

    func killJob(_ job: BackgroundJob) async {
        guard let sessionID = selectedSessionID else { return }
        do {
            _ = try await bridge.request("host.call", params: .object([
                "namespace": .string("job"),
                "method": .string("kill"),
                "args": .object([
                    "request": .object([
                        "sessionId": .string(sessionID),
                        "jobId": .string(job.id)
                    ])
                ])
            ]))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadOlderMessages() async {
        guard !isLoadingOlder, conversation.hasMore, let sessionID = selectedSessionID,
              let beforeSeq = conversation.firstSeq, conversation.lastSeq >= 0 else { return }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        do {
            let result = try await bridge.request("host.call", params: .object([
                "namespace": .string("session"),
                "method": .string("page"),
                "args": .object([
                    "request": .object([
                        "address": .object(["kind": .string("session"), "sessionId": .string(sessionID)]),
                        "throughSeq": .number(Double(conversation.lastSeq)),
                        "beforeSeq": .number(Double(beforeSeq)),
                        "maxMessages": .number(120)
                    ])
                ])
            ]), timeout: .seconds(30))
            let records = result["records"]?.arrayValue ?? []
            conversation.mergeOlder(records: records, hasMore: result["hasMore"]?.boolValue ?? false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func respondApproval(_ approval: PendingApproval, outcome: String) async {
        do {
            _ = try await bridge.request("approval.respond", params: .object([
                "eventId": .string(approval.eventId),
                "outcome": .string(outcome)
            ]))
        } catch {
            errorMessage = error.localizedDescription
        }
        pendingApprovals.removeAll { $0.eventId == approval.eventId }
    }

    func respondQuestion(_ question: PendingQuestion, answers: [[String: JSONValue]]) async {
        do {
            _ = try await bridge.request("question.respond", params: .object([
                "eventId": .string(question.eventId),
                "answers": .array(answers.map { .object($0) })
            ]))
        } catch {
            errorMessage = error.localizedDescription
        }
        pendingQuestions.removeAll { $0.eventId == question.eventId }
    }

    func cancelQuestion(_ question: PendingQuestion) async {
        do {
            _ = try await bridge.request("question.respond", params: .object([
                "eventId": .string(question.eventId),
                "cancelled": .bool(true)
            ]))
        } catch {
            errorMessage = error.localizedDescription
        }
        pendingQuestions.removeAll { $0.eventId == question.eventId }
    }

    func restartRuntime() async {
        connectionState = .starting
        eventStreamsOpened = false
        followStreamID = nil
        do {
            _ = try await bridge.request("runtime.restart", timeout: .seconds(75))
            await refreshSessions()
            await refreshModels()
            if let selectedSessionID { selectSession(selectedSessionID) }
        } catch {
            connectionState = .failed(error.localizedDescription)
            lastRuntimeError = error.localizedDescription
        }
    }

    func revealRuntimeLog() {
        guard let path = runtimeConfiguration?.dshHome else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }

    // MARK: - Host events

    private func handleHostEvent(name: String, args: [JSONValue]) {
        switch name {
        case "api-session/added":
            guard let value = args.first, let summary = try? value.decode(SessionSummary.self) else { return }
            upsert(summary: summary)
        case "api-session/removed":
            guard let sessionID = args.first?.stringValue else { return }
            sessions.removeAll { $0.sessionId == sessionID }
            if selectedSessionID == sessionID { selectSession(nil) }
        case "api-session/status":
            guard args.count >= 2, let sessionID = args[0].stringValue, let running = args[1].boolValue else { return }
            if let index = sessions.firstIndex(where: { $0.sessionId == sessionID }) {
                sessions[index] = sessions[index].replacingRunning(running)
            }
        case "api-session/activity":
            scheduleSessionRefresh()
        case "api-session/error":
            if args.count >= 2 {
                errorMessage = args[1]["message"]?.stringValue ?? args[1].stringValue ?? "The agent reported an error."
            }
        case "settings/document-updated", "llm/models-updated", "llm/adapters-updated":
            Task { await refreshModels() }
        case "commands/change":
            Task { await refreshCommands() }
        default:
            break
        }
    }

    private func upsert(summary: SessionSummary) {
        if let index = sessions.firstIndex(where: { $0.sessionId == summary.sessionId }) {
            sessions[index] = summary
        } else {
            sessions.append(summary)
        }
        sessions.sort { ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) }
    }
}

private extension SessionSummary {
    func replacingTitle(_ title: String?) -> SessionSummary {
        SessionSummary(
            sessionId: sessionId,
            updatedAt: updatedAt,
            running: running,
            blank: blank,
            cwd: cwd,
            agentAvailable: agentAvailable,
            formatStatus: formatStatus,
            parentSessionId: parentSessionId,
            origin: origin,
            projections: ProjectionHints(
                kind: projections?.kind,
                asOfSeq: projections?.asOfSeq,
                values: {
                    var values = projections?.values ?? [:]
                    values["title"] = title.map(JSONValue.string) ?? .null
                    return values
                }()
            )
        )
    }

    func replacingRunning(_ running: Bool?) -> SessionSummary {
        SessionSummary(
            sessionId: sessionId,
            updatedAt: updatedAt,
            running: running,
            blank: blank,
            cwd: cwd,
            agentAvailable: agentAvailable,
            formatStatus: formatStatus,
            parentSessionId: parentSessionId,
            origin: origin,
            projections: projections
        )
    }
}
