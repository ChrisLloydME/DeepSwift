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
    private var stdoutBuffer = Data()
    private var stderrText = ""
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

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { await self?.ingestStdout(data) }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { await self?.ingestStderr(text) }
        }
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
        stdinHandle = nil
        stdoutHandle?.readabilityHandler = nil
        stderrHandle?.readabilityHandler = nil
        stdoutHandle = nil
        stderrHandle = nil
        stdoutBuffer.removeAll(keepingCapacity: false)
        stopping = false
    }

    // MARK: - Inbound

    private func ingestStdout(_ data: Data) {
        stdoutBuffer.append(data)
        while let newline = stdoutBuffer.firstIndex(of: 0x0A) {
            let line = stdoutBuffer[..<newline]
            stdoutBuffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            handle(line: Data(line))
        }
        // A malformed or non-newline-terminated frame must not grow forever.
        if stdoutBuffer.count > 64 * 1024 * 1024 {
            stdoutBuffer.removeAll(keepingCapacity: false)
            notificationContinuation.yield(BridgeNotification(
                event: "bridge.malformed",
                data: .string("The bridge emitted an oversized frame.")
            ))
        }
    }

    private func handle(line: Data) {
        struct Inbound: Decodable {
            let id: String?
            let result: JSONValue?
            let error: BridgeResponseError?
            let event: String?
            let data: JSONValue?
        }
        let inbound: Inbound
        do {
            inbound = try JSONDecoder().decode(Inbound.self, from: line)
        } catch {
            notificationContinuation.yield(BridgeNotification(
                event: "bridge.malformed",
                data: .string(String(data: line, encoding: .utf8) ?? "Unreadable bridge frame")
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
        let detail = stderrText.isEmpty ? "" : "\n\(stderrText.suffix(2_000))"
        finishProcess(error: BridgeClientError.transportClosed(
            "The local DSH bridge exited with status \(process.terminationStatus).\(detail)"
        ))
        self.process = nil
        stdinHandle = nil
        stdoutHandle?.readabilityHandler = nil
        stderrHandle?.readabilityHandler = nil
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
