#!/usr/bin/env node
/**
 * DeepSwift bridge: a thin, dependency-free stdio JSON service in front of an
 * isolated official DeepSeek Harness Host.
 *
 * The bridge owns only process lifecycle, the authenticated HTTP carrier, and
 * the logical stream multiplexer. Session, workspace, file, approval, and
 * agent semantics remain in the official DSH Host.
 */

import { createInterface } from 'node:readline'
import { existsSync, readFileSync, statSync, appendFileSync, mkdirSync } from 'node:fs'
import { isAbsolute, dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { HostRuntime } from './host-process.mjs'
import { HostConnection } from './connection.mjs'
import { BridgeError, PROTOCOL_VERSION, parseRequestLine } from './protocol.mjs'

const HERE = dirname(fileURLToPath(import.meta.url))
const BOOT_TIME = Date.now()
const PARENT_PID = process.ppid

/** Resolved launch configuration. */
function readConfiguration() {
  const nodeBin = process.env.DEEPSWIFT_NODE_BIN
  const hostBin = process.env.DEEPSWIFT_DSH_BIN
  const home = process.env.DEEPSWIFT_DSH_HOME
  if (typeof nodeBin !== 'string' || !isAbsolute(nodeBin) || !existsSync(nodeBin)) {
    throw new BridgeError('bridge/configuration', 'DEEPSWIFT_NODE_BIN must name an existing absolute Node executable')
  }
  if (typeof hostBin !== 'string' || !isAbsolute(hostBin) || !existsSync(hostBin) || !statSync(hostBin).isFile()) {
    throw new BridgeError('bridge/configuration', 'DEEPSWIFT_DSH_BIN must name the official dsh bin.js')
  }
  if (typeof home !== 'string' || !isAbsolute(home)) {
    throw new BridgeError('bridge/configuration', 'DEEPSWIFT_DSH_HOME must be an explicit absolute directory')
  }
  const manifestPath = join(dirname(hostBin), '..', 'package.json')
  let dshVersion = 'unknown'
  try {
    dshVersion = JSON.parse(readFileSync(manifestPath, 'utf8')).version ?? 'unknown'
  } catch { /* reported as unknown; the Host still runs */ }
  return {
    nodeBin,
    hostBin,
    home: resolve(home),
    dshVersion,
    allowProviderEnv: process.env.DEEPSWIFT_ALLOW_PROVIDER_ENV === '1',
    cwd: process.env.DEEPSWIFT_BRIDGE_CWD,
    patches: (process.env.DEEPSWIFT_PATCH_FILES ?? '').split(':').filter(value => value.length > 0),
    logPath: join(resolve(home), 'logs', 'bridge.log'),
  }
}

let configuration
try {
  configuration = readConfiguration()
} catch (error) {
  write({ event: 'bridge.failed', data: { code: error.code ?? 'bridge/configuration', message: error.message } })
  process.exitCode = 1
  process.exit(1)
}

mkdirSync(dirname(configuration.logPath), { recursive: true, mode: 0o700 })
let stdoutWritable = true
let stdoutClosed = false
let stderrWritable = true

function logLine(text) {
  try { appendFileSync(configuration.logPath, `${new Date().toISOString()} ${text}\n`) } catch { /* diagnostics never break the bridge */ }
  if (!stderrWritable) return
  try { process.stderr.write(`[deepswift-bridge] ${text}\n`) } catch { stderrWritable = false }
}

function onStdoutClosed() {
  if (stdoutClosed) return
  stdoutClosed = true
  stdoutWritable = false
  // The application disappeared. Stop the Host instead of becoming an orphan.
  void shutdown(0)
}

function write(frame) {
  if (!stdoutWritable) return
  try {
    process.stdout.write(`${JSON.stringify(frame)}\n`)
  } catch {
    onStdoutClosed()
  }
}

function emit(event, data) {
  write({ event, data })
}

process.stdout.on('error', () => { onStdoutClosed() })
process.stderr.on('error', () => { stderrWritable = false })
process.stdin.on('error', () => { void shutdown(0) })

let runtime
let connection
let clientId
let hostState = 'idle'
let starting
let reconnectTimer
let reconnectAttempt = 0
let shuttingDown = false
const swiftStreams = new Map()
const pendingInteractions = new Map()
let eventStreamPresent = false

function hostFacts() {
  return {
    state: hostState,
    home: configuration.home,
    dshVersion: configuration.dshVersion,
    nodeVersion: process.version,
    bridgePid: process.pid,
    hostPid: runtime?.isRunning === true ? runtime.childPid ?? null : null,
    hostUrl: runtime?.url ?? null,
    clientId: clientId ?? null,
    eventStreamReady: eventStreamPresent,
    uptimeMs: Date.now() - BOOT_TIME,
  }
}

function logTail() {
  return runtime?.stderrTail ?? ''
}

async function startHost() {
  if (starting !== undefined) return starting
  starting = (async () => {
    hostState = 'starting'
    emit('runtime.starting', { home: configuration.home, dshVersion: configuration.dshVersion })
    runtime = new HostRuntime({
      nodeBin: configuration.nodeBin,
      hostBin: configuration.hostBin,
      home: configuration.home,
      ...(configuration.cwd === undefined ? {} : { cwd: configuration.cwd }),
      patches: configuration.patches,
      allowProviderEnv: configuration.allowProviderEnv,
    })
    runtime.on('exit', ({ code, signal, stderr }) => {
      hostState = 'exited'
      eventStreamPresent = false
      clientId = undefined
      failPendingInteractions('Host process exited')
      if (!shuttingDown) emit('runtime.exited', { code, signal, stderr: stderr.slice(-8000) })
    })
    let url
    try {
      url = await runtime.start()
    } catch (error) {
      hostState = 'failed'
      logLine(`host start failed: ${error instanceof Error ? error.message : String(error)}`)
      emit('runtime.failed', {
        code: error instanceof BridgeError ? error.code : 'runtime/start-failed',
        message: error instanceof Error ? error.message : String(error),
        stderr: logTail().slice(-8000),
      })
      return false
    }
    const parsed = new URL(url)
    const token = parsed.searchParams.get('token')
    if (token === null) {
      hostState = 'failed'
      emit('runtime.failed', { code: 'runtime/protocol', message: 'DSH ready URL carried no launch token' })
      return false
    }
    connection = new HostConnection(parsed.origin, token)
    try {
      await connection.authenticate()
      connection.on('mux-close', () => onMuxClosed())
      connection.on('error', (error) => logLine(`mux error: ${error.message}`))
      await connection.openMux()
      openEventStream()
      hostState = 'ready'
      reconnectAttempt = 0
      emit('runtime.ready', { ...hostFacts(), startedAt: Date.now() })
      return true
    } catch (error) {
      hostState = 'failed'
      logLine(`connect failed: ${error instanceof Error ? error.message : String(error)}`)
      emit('runtime.failed', {
        code: error instanceof BridgeError ? error.code : 'runtime/connect-failed',
        message: error instanceof Error ? error.message : String(error),
        stderr: logTail().slice(-8000),
      })
      return false
    }
  })().finally(() => { starting = undefined })
  return starting
}

function openEventStream() {
  if (connection === undefined || !connection.isMuxOpen) return
  if (eventStreamPresent) return
  eventStreamPresent = true
  clientId = undefined
  try {
    connection.openStream('$events', '$events', {}, {
      onItem: handleEventFrame,
      onError: (error) => {
        eventStreamPresent = false
        clientId = undefined
        logLine(`event stream error: ${error.message}`)
        emit('host.eventStreamFailed', { message: error.message })
      },
      onEnd: () => {
        eventStreamPresent = false
        clientId = undefined
        logLine('event stream ended')
      },
      onReset: () => {
        eventStreamPresent = false
        clientId = undefined
      },
    })
  } catch (error) {
    eventStreamPresent = false
    logLine(`event stream open failed: ${error instanceof Error ? error.message : String(error)}`)
  }
}

function handleEventFrame(frame) {
  if (frame === null || typeof frame !== 'object') return
  if (frame.type === 'ready') {
    clientId = frame.clientId
    eventStreamPresent = true
    emit('host.connected', { clientId: frame.clientId, host: frame.host, reconnected: reconnectAttempt > 0 })
    return
  }
  if (frame.type === 'emit') {
    emit('host.event', { event: frame.event, args: frame.args })
    return
  }
  if (frame.type === 'waterfall') {
    if (frame.event === 'approval/request') {
      const pending = { kind: 'approval', frame, clientId, receivedAt: Date.now() }
      pendingInteractions.set(frame.eventId, pending)
      emit('approval.request', {
        eventId: frame.eventId,
        sessionId: frame.agentId,
        toolName: frame.request.toolName,
        ...(frame.request.callId === undefined ? {} : { callId: frame.request.callId }),
        ...(frame.request.reason === undefined ? {} : { reason: frame.request.reason }),
        ...(frame.request.displayReason === undefined ? {} : { displayReason: frame.request.displayReason }),
      })
      return
    }
    if (frame.event === 'user-questions/request') {
      const pending = { kind: 'question', frame, clientId, receivedAt: Date.now() }
      pendingInteractions.set(frame.eventId, pending)
      emit('question.request', { eventId: frame.eventId, ...frame.request })
      return
    }
    // Unknown interactive waterfalls fail closed: do not claim them, and let the
    // Host's own answerer chain decide. Never auto-approve.
    logLine(`unhandled waterfall event ${frame.event}`)
    void replyWaterfall(frame.eventId, { kind: 'next' }).catch((error) => logLine(`delegate failed: ${error.message}`))
    return
  }
  if (frame.type === 'cancel') {
    const pending = pendingInteractions.get(frame.eventId)
    if (pending !== undefined) {
      pendingInteractions.delete(frame.eventId)
      emit(pending.kind === 'question' ? 'question.cancelled' : 'approval.cancelled', { eventId: frame.eventId })
    }
  }
}

function onMuxClosed() {
  eventStreamPresent = false
  clientId = undefined
  failPendingInteractions('Connection generation ended')
  if (hostState === 'ready') hostState = 'degraded'
  emit('host.disconnected', { state: hostState })
  scheduleReconnect()
}

function scheduleReconnect() {
  if (shuttingDown || runtime === undefined || !runtime.isRunning) return
  if (reconnectTimer !== undefined) return
  const delay = Math.min(500 * 2 ** reconnectAttempt, 8_000)
  reconnectAttempt += 1
  emit('host.reconnecting', { attempt: reconnectAttempt, delayMs: delay, maxAttempts: null })
  reconnectTimer = setTimeout(async () => {
    reconnectTimer = undefined
    if (shuttingDown || connection === undefined) return
    try {
      await connection.authenticate()
      await connection.openMux()
      eventStreamPresent = false
      // A fresh physical generation starts a fresh logical event stream.
      connection.closeStream('$events')
      openEventStream()
      connection.reopenStreams()
      hostState = 'ready'
      reconnectAttempt = 0
      emit('host.reconnected', { ...hostFacts(), startedAt: Date.now() })
    } catch (error) {
      logLine(`reconnect failed: ${error instanceof Error ? error.message : String(error)}`)
      if (connection !== undefined) {
        try { connection.close() } catch { /* already closed */ }
      }
      scheduleReconnect()
    }
  }, delay)
  reconnectTimer.unref?.()
}

function failPendingInteractions(reason) {
  for (const [eventId, pending] of pendingInteractions) {
    emit(pending.kind === 'question' ? 'question.cancelled' : 'approval.cancelled', { eventId, reason })
  }
  pendingInteractions.clear()
}

async function replyWaterfall(eventId, outcome) {
  if (connection === undefined || clientId === undefined) throw new BridgeError('interaction/offline', 'Host connection is not ready')
  await connection.rpc('$events', 'result', { clientId, eventId, outcome })
}

async function respondInteraction(eventId, outcome) {
  const pending = pendingInteractions.get(eventId)
  if (pending === undefined) throw new BridgeError('interaction/unknown', `No pending interaction ${eventId}`)
  if (connection === undefined || clientId === undefined) throw new BridgeError('interaction/offline', 'Host connection is not ready')
  const result = { clientId, eventId, outcome }
  try {
    await connection.rpc('$events', 'result', result)
  } catch (error) {
    pendingInteractions.delete(eventId)
    shortError(event)
  }
  pendingInteractions.delete(eventId)
  return { accepted: true }
}

function shortError(error) {
  if (error instanceof BridgeError) throw error
  throw new BridgeError('bridge/internal', error instanceof Error ? error.message : String(error))
}

async function dispatch(method, params) {
  switch (method) {
    case 'bridge.status':
      return { ...hostFacts(), protocolVersion: PROTOCOL_VERSION }
    case 'runtime.status':
      return hostFacts()
    case 'runtime.start':
      await startHost()
      return hostFacts()
    case 'runtime.restart': {
      await stopRuntime()
      const started = await startHost()
      if (!started) throw new BridgeError('runtime/start-failed', 'DSH Host did not start', { stderr: logTail().slice(-8000) })
      return hostFacts()
    }
    case 'runtime.logs':
      return { stderr: logTail().slice(-16_000), logPath: configuration.logPath }
    case 'host.call': {
      if (connection === undefined || hostState !== 'ready') throw new BridgeError('connection/not-ready', 'DSH Host is not ready')
      const { namespace, method: remoteMethod, args, timeoutMs } = params
      if (typeof namespace !== 'string' || typeof remoteMethod !== 'string') {
        throw new BridgeError('bridge/invalid-request', 'host.call requires namespace and method')
      }
      return connection.rpc(namespace, remoteMethod, args ?? {}, { ...(typeof timeoutMs === 'number' ? { timeoutMs } : {}) })
    }
    case 'stream.open': {
      if (connection === undefined || !connection.isMuxOpen) throw new BridgeError('connection/not-ready', 'Remote stream socket is not connected')
      const { id, endpoint, args } = params
      if (typeof id !== 'string' || typeof endpoint !== 'string') {
        throw new BridgeError('bridge/invalid-request', 'stream.open requires id and endpoint')
      }
      if (id === '$events') throw new BridgeError('bridge/invalid-request', 'Reserved stream id')
      connection.openStream(id, endpoint, args ?? {}, {
        onItem: (value) => emit('stream.item', { id, value }),
        onError: (error) => {
          swiftStreams.delete(id)
          emit('stream.error', { id, code: error.code, message: error.message, details: error.details ?? {} })
        },
        onEnd: () => {
          swiftStreams.delete(id)
          emit('stream.end', { id })
        },
        onReset: (info) => emit('stream.reset', { id, code: info?.code ?? null, reason: info?.reason ?? 'carrier reset' }),
      })
      swiftStreams.set(id, { id, endpoint, args: args ?? {} })
      return { opened: true }
    }
    case 'stream.close': {
      const { id } = params
      if (typeof id !== 'string') throw new BridgeError('bridge/invalid-request', 'stream.close requires id')
      connection?.closeStream(id)
      swiftStreams.delete(id)
      return { closed: true }
    }
    case 'stream.send': {
      const { id, value } = params
      if (typeof id !== 'string') throw new BridgeError('bridge/invalid-request', 'stream.send requires id')
      connection?.sendStreamItem(id, value)
      return { accepted: true }
    }
    case 'stream.end': {
      const { id } = params
      if (typeof id !== 'string') throw new BridgeError('bridge/invalid-request', 'stream.end requires id')
      connection?.endStream(id)
      return { accepted: true }
    }
    case 'account.state': {
      if (connection === undefined || hostState !== 'ready') throw new BridgeError('connection/not-ready', 'DSH Host is not ready')
      return connection.rpc('account', 'getState', {})
    }
    case 'account.signIn': {
      if (connection === undefined || hostState !== 'ready') throw new BridgeError('connection/not-ready', 'DSH Host is not ready')
      const locale = Intl.DateTimeFormat().resolvedOptions().locale || 'en'
      const client = {
        version: process.env.DEEPSWIFT_CLIENT_VERSION ?? '0.1.0',
        locale,
        timezoneOffsetSeconds: -new Date().getTimezoneOffset() * 60,
      }
      return connection.rpc('account', 'startSignIn', {
        client,
        callbackOrigin: connection.baseUrl,
        loginSource: 'desktop',
      }, { timeoutMs: 30_000 })
    }
    case 'account.cancelSignIn': {
      if (connection === undefined || hostState !== 'ready') throw new BridgeError('connection/not-ready', 'DSH Host is not ready')
      const { attemptId } = params
      if (typeof attemptId !== 'string' || attemptId.length === 0) throw new BridgeError('bridge/invalid-request', 'account.cancelSignIn requires attemptId')
      return connection.rpc('account', 'cancelSignIn', { attemptId }, { timeoutMs: 30_000 })
    }
    case 'account.signOut': {
      if (connection === undefined || hostState !== 'ready') throw new BridgeError('connection/not-ready', 'DSH Host is not ready')
      const locale = Intl.DateTimeFormat().resolvedOptions().locale || 'en'
      const client = {
        version: process.env.DEEPSWIFT_CLIENT_VERSION ?? '0.1.0',
        locale,
        timezoneOffsetSeconds: -new Date().getTimezoneOffset() * 60,
      }
      return connection.rpc('account', 'signOut', { client }, { timeoutMs: 30_000 })
    }
    case 'account.profile': {
      if (connection === undefined || hostState !== 'ready') throw new BridgeError('connection/not-ready', 'DSH Host is not ready')
      const locale = Intl.DateTimeFormat().resolvedOptions().locale || 'en'
      const client = {
        version: process.env.DEEPSWIFT_CLIENT_VERSION ?? '0.1.0',
        locale,
        timezoneOffsetSeconds: -new Date().getTimezoneOffset() * 60,
      }
      return connection.rpc('account', 'getProfile', { client }, { timeoutMs: 30_000 })
    }
    case 'approval.respond': {
      const { eventId, outcome } = params
      if (typeof eventId !== 'string') throw new BridgeError('bridge/invalid-request', 'approval.respond requires eventId')
      if (outcome !== 'allowed-once' && outcome !== 'rejected' && outcome !== 'cancelled' && outcome !== 'unavailable') {
        throw new BridgeError('bridge/invalid-request', 'Approval outcome is not part of the closed vocabulary')
      }
      return respondInteraction(eventId, { kind: 'result', value: outcome })
    }
    case 'question.respond': {
      const { eventId, answers, cancelled } = params
      if (typeof eventId !== 'string') throw new BridgeError('bridge/invalid-request', 'question.respond requires eventId')
      if (cancelled === true) return respondInteraction(eventId, { kind: 'result', value: { cancelled: true } })
      if (!Array.isArray(answers)) throw new BridgeError('bridge/invalid-request', 'question.respond requires answers or cancelled')
      return respondInteraction(eventId, { kind: 'result', value: { answers } })
    }
    case 'question.delegate': {
      const { eventId } = params
      return respondInteraction(eventId, { kind: 'next' })
    }
    case 'diagnostics.record': {
      const { message } = params
      logLine(`client: ${typeof message === 'string' ? message : JSON.stringify(message)}`)
      return { recorded: true }
    }
    case 'shutdown':
      return { accepted: true, shutdown: true }
    default:
      throw new BridgeError('bridge/unknown-method', `Unknown bridge method ${method}`)
  }
}

async function stopRuntime() {
  failPendingInteractions('Bridge is stopping')
  if (connection !== undefined) {
    try { connection.close() } catch { /* closing */ }
    connection = undefined
  }
  if (runtime !== undefined) {
    try { await runtime.stop() } catch (error) { logLine(`host stop failed: ${error.message}`) }
    runtime = undefined
  }
  hostState = 'stopped'
  eventStreamPresent = false
  clientId = undefined
}

async function shutdown(code = 0) {
  if (shuttingDown) return
  shuttingDown = true
  clearTimeout(reconnectTimer)
  reconnectTimer = undefined
  stdoutWritable = false
  stderrWritable = false
  await stopRuntime()
  process.exit(code)
}

const rl = createInterface({ input: process.stdin, crlfDelay: Infinity })
rl.on('line', (line) => {
  let request
  try {
    request = parseRequestLine(line)
  } catch (error) {
    emit('bridge.protocolError', { message: error.message })
    return
  }
  if (request === null) return
  logLine(`request ${request.method}`)
  void dispatch(request.method, request.params)
    .then((result) => {
      write({ id: request.id, result })
      if (result?.shutdown === true) void shutdown(0)
    })
    .catch((error) => {
      const bridgeError = error instanceof BridgeError
        ? error
        : new BridgeError('bridge/internal', error instanceof Error ? error.message : String(error))
      if (bridgeError.code === 'bridge/unknown-method') logLine(`unknown method ${request.method}`)
      write({
        id: request.id,
        error: {
          code: bridgeError.code,
          message: bridgeError.message,
          ...(bridgeError.details === undefined ? {} : { details: bridgeError.details }),
        },
      })
    })
})
rl.on('close', () => { void shutdown(0) })

for (const signal of ['SIGINT', 'SIGTERM', 'SIGHUP']) {
  process.on(signal, () => { void shutdown(0) })
}

process.on('uncaughtException', (error) => {
  // A closed parent pipe raises EPIPE asynchronously. Writing diagnostics from
  // this path would raise it again, so silence both pipes before cleanup.
  stdoutWritable = false
  stderrWritable = false
  void shutdown(1)
})
process.on('unhandledRejection', (reason) => {
  logLine(`unhandled rejection: ${reason instanceof Error ? reason.stack ?? reason.message : String(reason)}`)
})

// The application owns this process. A parent crash can leave stdin open
// briefly (or indefinitely under a debugger), so a reparent check is the final
// orphan fence. Only this bridge's own parent identity is observed.
const parentWatchdog = setInterval(() => {
  if (process.ppid === 1 || process.ppid !== PARENT_PID) {
    logLine(`parent process ${PARENT_PID} disappeared; shutting down`)
    clearInterval(parentWatchdog)
    void shutdown(0)
  }
}, 2_000)
parentWatchdog.unref()

emit('bridge.hello', {
  protocolVersion: PROTOCOL_VERSION,
  home: configuration.home,
  dshVersion: configuration.dshVersion,
  nodeVersion: process.version,
  allowProviderEnv: configuration.allowProviderEnv,
  logPath: configuration.logPath,
})
void startHost()
