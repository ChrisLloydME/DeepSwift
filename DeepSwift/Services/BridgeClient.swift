//
//  BridgeClient.swift
//  DeepSwift
//

import Foundation
import OSLog

/// Transport boundary used by the application model.
///
/// The production implementation owns a Node child process. Tests provide a
/// mock with the same request/notification surface and never start a Host.
nonisolated protocol DSHBridgeService: Sendable {
    nonisolated var notifications: AsyncStream<BridgeNotification> { get }
    nonisolated func start(configuration: RuntimeConfiguration) async throws
    nonisolated func request(_ method: String, params: JSONValue, timeout: Duration) async throws -> JSONValue
    nonisolated func stop() async
}

nonisolated extension DSHBridgeService {
    /// Convenience overload for callers that use the bridge defaults.
    nonisolated func request(_ method: String, params: JSONValue = .object([:]), timeout: Duration = .seconds(30)) async throws -> JSONValue {
        try await request(method, params: params, timeout: timeout)
    }
}


/// Actor-isolated stdio client for the local DeepSwift bridge.
actor BridgeClient: DSHBridgeService {
    nonisolated let notifications: AsyncStream<BridgeNotification>

    private let notificationContinuation: AsyncStream<BridgeNotification>.Continuation
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?
    private var pending: [String: PendingRequest] = [:]
    private var stdoutBuffer = BridgeFrameBuffer()
    private var stderrText = ""
    private var stdoutReaderTask: Task<Void, Never>?
    private var stderrReaderTask: Task<Void, Never>?
    private var stdoutContinuation: AsyncStream<Data>.Continuation?
    private var stderrContinuation: AsyncStream<Data>.Continuation?
    private var stopping = false
    private let logger = Logger(subsystem: "com.lloydME.DeepSwift", category: "BridgeClient")

    private struct PendingRequest {
        let method: String
        let continuation: CheckedContinuation<JSONValue, Error>
        let timeoutTask: Task<Void, Never>
    }

    init() {
        let (stream, continuation) = AsyncStream<BridgeNotification>.makeStream(bufferingPolicy: .bufferingNewest(2_000))
        notifications = stream
        notificationContinuation = continuation
    }

    var stderrTail: String { stderrText }

    /// Provider keys that the caller opted to pass to the bridge child. The
    /// same prefix policy is enforced again for the Host child.
    nonisolated static func providerEnvironment(from environment: [String: String]) -> [String: String] {
        let prefixes = ["DEEPSEEK_", "OPENAI_", "ANTHROPIC_", "OPENCODE_"]
        return environment.filter { key, _ in
            prefixes.contains(where: { key.hasPrefix($0) })
        }
    }

    func start(configuration: RuntimeConfiguration) async throws {
        guard process == nil else { return }
        stopping = false

        let process = Process()
        process.executableURL = URL(fileURLWithPath: configuration.nodePath)
        process.arguments = [configuration.bridgePath]
        process.currentDirectoryURL = URL(fileURLWithPath: configuration.dshHome, isDirectory: true)

        var environment: [String: String] = [
            "DEEPSWIFT_NODE_BIN": configuration.nodePath,
            "DEEPSWIFT_DSH_BIN": configuration.dshBinPath,
            "DEEPSWIFT_DSH_HOME": configuration.dshHome,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin",
            "LANG": Locale.current.identifier,
            "NO_COLOR": "1"
        ]
        if let home = ProcessInfo.processInfo.environment["HOME"] {
            environment["HOME"] = home
        }
        if let tmp = ProcessInfo.processInfo.environment["TMPDIR"] {
            environment["TMPDIR"] = tmp
        }
        if configuration.allowProviderEnv {
            environment["DEEPSWIFT_ALLOW_PROVIDER_ENV"] = "1"
            for (key, value) in Self.providerEnvironment(from: ProcessInfo.processInfo.environment) {
                environment[key] = value
            }
        }
        process.environment = environment

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stdinHandle = stdinPipe.fileHandleForWriting
        stdoutHandle = stdoutPipe.fileHandleForReading
        stderrHandle = stderrPipe.fileHandleForReading
        process.terminationHandler = { [weak self] process in
            Task { await self?.handleTermination(process) }
        }

        do {
            try process.run()
        } catch {
            stdinHandle = nil
            stdoutHandle = nil
            stderrHandle = nil
            throw BridgeClientError.launchFailed("Could not launch the local bridge: \(error.localizedDescription)")
        }
        self.process = process
        logger.info("Bridge launched pid \(process.processIdentifier, privacy: .public)")

        // Readability callbacks can arrive on different queues. Feed their
        // bytes into one ordered stream and consume that stream from a single
        // task, rather than spawning a task per callback (which can reorder a
        // large frame).
        let (stdoutStream, stdoutContinuation) = AsyncStream<Data>.makeStream(
            bufferingPolicy: .unbounded
        )
        let (stderrStream, stderrContinuation) = AsyncStream<Data>.makeStream(
            bufferingPolicy: .unbounded
        )
        self.stdoutContinuation = stdoutContinuation
        self.stderrContinuation = stderrContinuation
        let stdoutReadLock = NSLock()
        let stderrReadLock = NSLock()

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            stdoutReadLock.lock()
            defer { stdoutReadLock.unlock() }
            let data = handle.availableData
            if data.isEmpty {
                stdoutContinuation.finish()
                handle.readabilityHandler = nil
            } else {
                stdoutContinuation.yield(data)
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            stderrReadLock.lock()
            defer { stderrReadLock.unlock() }
            let data = handle.availableData
            if data.isEmpty {
                stderrContinuation.finish()
                handle.readabilityHandler = nil
            } else {
                stderrContinuation.yield(data)
            }
        }

        stdoutReaderTask = Task.detached(priority: .userInitiated) { [weak self] in
            for await data in stdoutStream {
                guard !Task.isCancelled else { return }
                await self?.ingestStdout(data)
            }
        }
        stderrReaderTask = Task.detached(priority: .utility) { [weak self] in
            for await data in stderrStream {
                guard !Task.isCancelled else { return }
                let text = String(decoding: data, as: UTF8.self)
                await self?.ingestStderr(text)
            }
        }
    }

    func request(_ method: String, params: JSONValue = .object([:]), timeout: Duration = .seconds(30)) async throws -> JSONValue {
        guard let process, process.isRunning, let stdinHandle else {
            throw BridgeClientError.notRunning
        }
        let id = UUID().uuidString
        let request = BridgeRequest(id: id, method: method, params: params)
        var data = try JSONEncoder().encode(request)
        data.append(0x0A)

        return try await withCheckedThrowingContinuation { continuation in
            let timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                await self?.timeout(id: id, method: method)
            }
            pending[id] = PendingRequest(method: method, continuation: continuation, timeoutTask: timeoutTask)
            do {
                try stdinHandle.write(contentsOf: data)
            } catch {
                if let request = pending.removeValue(forKey: id) {
                    request.timeoutTask.cancel()
                    request.continuation.resume(throwing: BridgeClientError.transportClosed("The bridge input pipe closed."))
                }
            }
        }
    }

    func stop() async {
        guard let process else { return }
        stopping = true
        if process.isRunning {
            _ = try? await request("shutdown", timeout: .seconds(2))
            try? await Task.sleep(for: .milliseconds(250))
        }
        if process.isRunning {
            stdinHandle?.closeFile()
            try? await Task.sleep(for: .milliseconds(400))
        }
        if process.isRunning {
            process.terminate()
            try? await Task.sleep(for: .milliseconds(600))
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
        finishProcess(error: BridgeClientError.transportClosed("The bridge stopped."))
        self.process = nil
        stdoutReaderTask?.cancel()
        stderrReaderTask?.cancel()
        stdoutReaderTask = nil
        stderrReaderTask = nil
        stdoutContinuation?.finish()
        stderrContinuation?.finish()
        stdoutContinuation = nil
        stderrContinuation = nil
        stdinHandle = nil
        stdoutHandle?.readabilityHandler = nil
        stderrHandle?.readabilityHandler = nil
        stdoutHandle?.closeFile()
        stderrHandle?.closeFile()
        stdoutHandle = nil
        stderrHandle = nil
        stdoutBuffer.reset()
        stopping = false
    }

    // MARK: - Inbound

    private func ingestStdout(_ data: Data) {
        for line in stdoutBuffer.append(data) {
            handle(line: line)
        }
        // A malformed or non-newline-terminated frame must not grow forever.
        // The frame itself is discarded; only its size is reported.
        if let byteCount = stdoutBuffer.discardOversizedFrame() {
            notificationContinuation.yield(BridgeNotification(
                event: "bridge.malformed",
                data: .object([
                    "code": .string("bridge/frame-too-large"),
                    "message": .string("The local runtime emitted an oversized protocol frame."),
                    "bytes": .number(Double(byteCount))
                ])
            ))
        }
    }

    private func handle(line: Data) {
        let inbound: BridgeInboundEnvelope
        do {
            inbound = try JSONDecoder().decode(BridgeInboundEnvelope.self, from: line)
        } catch {
            // A valid JSON document can still expose a trustworthy top-level
            // string id. If it does, fail exactly that request now instead of
            // leaving it pending until its timeout. Never grep the raw text for
            // an id: only a parsed JSON field is considered reliable.
            if let id = Self.topLevelID(in: line), let request = pending.removeValue(forKey: id) {
                request.timeoutTask.cancel()
                request.continuation.resume(throwing: BridgeClientError.protocolViolation(
                    "The local runtime returned a response that could not be decoded."
                ))
            }
            notificationContinuation.yield(BridgeNotification(
                event: "bridge.malformed",
                data: .object([
                    "code": .string("bridge/frame-decode"),
                    "message": .string("The local runtime returned a response DeepSwift could not decode."),
                    "bytes": .number(Double(line.count)),
                    "reason": .string(Self.decodingReason(error))
                ])
            ))
            return
        }
        if let event = inbound.event {
            notificationContinuation.yield(BridgeNotification(event: event, data: inbound.data ?? .null))
            return
        }
        guard let id = inbound.id, let request = pending.removeValue(forKey: id) else { return }
        request.timeoutTask.cancel()
        if let error = inbound.error {
            request.continuation.resume(throwing: BridgeClientError.bridge(
                code: error.code,
                message: error.message,
                details: error.details
            ))
        } else {
            request.continuation.resume(returning: inbound.result ?? .null)
        }
    }

    /// Parses only the top-level `id` field. Returns nil unless the JSON parses
    /// and `id` is a string. No substring matching or payload retention.
    private static func topLevelID(in line: Data) -> String? {
        struct IDProbe: Decodable { let id: String? }
        return (try? JSONDecoder().decode(IDProbe.self, from: line))?.id
    }

    private static func decodingReason(_ error: Error) -> String {
        guard let decoding = error as? DecodingError else {
            return "The frame was not valid protocol JSON."
        }
        switch decoding {
        case let .keyNotFound(key, context):
            return "Missing \(Self.codingPath(context.codingPath + [key]))"
        case let .typeMismatch(_, context):
            return "Unexpected type at \(Self.codingPath(context.codingPath))"
        case let .valueNotFound(_, context):
            return "Missing value at \(Self.codingPath(context.codingPath))"
        case .dataCorrupted:
            return "Malformed JSON value"
        @unknown default:
            return "The frame was not valid protocol JSON."
        }
    }

    private static func codingPath(_ path: [CodingKey]) -> String {
        guard !path.isEmpty else { return "the frame root" }
        return path.map(\.stringValue).joined(separator: ".")
    }

    private func ingestStderr(_ text: String) {
        stderrText.append(text)
        if stderrText.count > 64_000 {
            stderrText = String(stderrText.suffix(48_000))
        }
        notificationContinuation.yield(BridgeNotification(event: "bridge.log", data: .string(text)))
    }

    private func timeout(id: String, method: String) {
        guard let request = pending.removeValue(forKey: id) else { return }
        request.timeoutTask.cancel()
        request.continuation.resume(throwing: BridgeClientError.timedOut(method))
    }

    private func handleTermination(_ process: Process) {
        guard self.process === process else { return }
        let safeTail = AppErrorPresentationFactory.sanitizedDetails(
            String(stderrText.suffix(4_000)),
            limit: 2_000
        ) ?? ""
        let detail = safeTail.isEmpty ? "" : "\n\(safeTail)"
        finishProcess(error: BridgeClientError.transportClosed(
            "The local DSH bridge exited with status \(process.terminationStatus).\(detail)"
        ))
        self.process = nil
        stdoutReaderTask?.cancel()
        stderrReaderTask?.cancel()
        stdoutReaderTask = nil
        stderrReaderTask = nil
        stdoutContinuation?.finish()
        stderrContinuation?.finish()
        stdoutContinuation = nil
        stderrContinuation = nil
        stdinHandle = nil
        stdoutHandle?.readabilityHandler = nil
        stderrHandle?.readabilityHandler = nil
        stdoutHandle?.closeFile()
        stderrHandle?.closeFile()
        stdoutHandle = nil
        stderrHandle = nil
        let wasStopping = stopping
        notificationContinuation.yield(BridgeNotification(
            event: "bridge.exited",
            data: .object([
                "status": .number(Double(process.terminationStatus)),
                "reason": .number(Double(process.terminationReason.rawValue)),
                "wasStopping": .bool(wasStopping)
            ])
        ))
    }

    private func finishProcess(error: Error) {
        let requests = pending
        pending.removeAll()
        for (_, request) in requests {
            request.timeoutTask.cancel()
            request.continuation.resume(throwing: error)
        }
    }
}
