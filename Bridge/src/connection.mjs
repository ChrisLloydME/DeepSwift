/**
 * Authenticated HTTP + WebSocket connection to one DSH Host generation.
 *
 * Authentication follows the official API-client flow:
 *   GET /connect?token=...&interactions=answer -> 302 + API cookie
 * Every RPC then POSTs a Connection envelope to /api/<namespace>/<method>,
 * and every live stream opens a logical stream on /api/remote.mux.
 */

import { EventEmitter } from 'node:events'
import { randomUUID } from 'node:crypto'
import { WebSocketClient } from './websocket.mjs'
import { BridgeError } from './protocol.mjs'

const DEFAULT_RPC_TIMEOUT_MS = 30_000

/** One authenticated connection. */
export class HostConnection extends EventEmitter {
  #baseUrl
  #token
  #cookie
  #mux
  #streams = new Map()
  #muxReady = false

  constructor(baseUrl, token) {
    super()
    this.#baseUrl = baseUrl.replace(/\/$/, '')
    this.#token = token
  }

  get baseUrl() {
    return this.#baseUrl
  }

  /** Exchange the launch token for an API cookie. */
  async authenticate({ interactions = 'answer' } = {}) {
    const url = new URL('/connect', this.#baseUrl)
    url.searchParams.set('token', this.#token)
    url.searchParams.set('interactions', interactions)
    const response = await fetch(url, { redirect: 'manual' })
    if (response.status !== 302) {
      const body = await response.text().catch(() => '')
      throw new BridgeError('connection/unauthorized', `DSH connect failed with HTTP ${response.status}`, { body: body.slice(0, 300) })
    }
    const setCookie = response.headers.get('set-cookie')
    if (setCookie === null || setCookie.length === 0) {
      throw new BridgeError('connection/unauthorized', 'DSH connect returned no API cookie')
    }
    this.#cookie = setCookie.split(';', 1)[0]
    return { cookie: this.#cookie }
  }

  /** Call one unary Remote endpoint. */
  async rpc(namespace, method, args = {}, { timeoutMs = DEFAULT_RPC_TIMEOUT_MS } = {}) {
    if (this.#cookie === undefined) throw new BridgeError('connection/not-authenticated', 'Authenticate before calling the Host')
    const endpoint = `${namespace}/${method}`
    const rpcId = randomUUID()
    const body = JSON.stringify({ type: 'client-request', rpcId, method: endpoint, payload: { args } })
    let response
    try {
      response = await fetch(`${this.#baseUrl}/api/${namespace}/${method}`, {
        method: 'POST',
        headers: { 'content-type': 'application/json', cookie: this.#cookie },
        body,
        signal: AbortSignal.timeout(timeoutMs),
      })
    } catch (error) {
      throw new BridgeError('connection/transport', error instanceof Error ? error.message : String(error), { endpoint })
    }
    const text = await response.text()
    if (!response.ok) {
      throw new BridgeError('connection/http', `Host answered HTTP ${response.status}`, { endpoint, body: text.slice(0, 500) })
    }
    let envelope
    try {
      envelope = JSON.parse(text)
    } catch {
      throw new BridgeError('connection/protocol', 'Host response is not JSON', { endpoint, body: text.slice(0, 300) })
    }
    if (envelope?.type !== 'server-response' || envelope.rpcId !== rpcId || typeof envelope.result !== 'object') {
      throw new BridgeError('connection/protocol', 'Host response envelope is invalid', { endpoint })
    }
    if (envelope.result.ok !== true) {
      const error = envelope.result.error ?? {}
      throw new BridgeError(`host/${error.code ?? 'unknown'}`, error.message ?? 'Host call failed', {
        endpoint,
        ...(typeof error.details === 'object' && error.details !== null ? { details: error.details } : {}),
      })
    }
    return envelope.result.value
  }

  /** Open the multiplexed Remote stream socket. */
  async openMux() {
    if (this.#cookie === undefined) throw new BridgeError('connection/not-authenticated', 'Authenticate before opening streams')
    const wsUrl = `${this.#baseUrl.replace(/^http/, 'ws')}/api/remote.mux`
    const socket = await WebSocketClient.connect(wsUrl, { cookie: this.#cookie })
    this.#mux = socket
    this.#muxReady = true
    socket.on('message', (text) => this.#onMuxMessage(text))
    socket.on('error', (error) => this.emit('error', error))
    socket.on('close', (info) => {
      this.#muxReady = false
      this.#mux = undefined
      for (const stream of this.#streams.values()) stream.onReset?.(info)
      this.emit('mux-close', info)
    })
    return socket
  }

  get isMuxOpen() {
    return this.#muxReady
  }

  /**
   * Open one logical stream.
   * @param {string} id - bridge-level stream identity.
   * @param {string} endpoint - Remote endpoint, e.g. session/follow.
   * @param {object} args - positional args object.
   * @param {{onItem?:Function,onError?:Function,onEnd?:Function,onReset?:Function}} handlers
   */
  openStream(id, endpoint, args, handlers = {}) {
    if (!this.#muxReady) throw new BridgeError('connection/not-connected', 'Remote stream socket is not connected')
    if (this.#streams.has(id)) throw new BridgeError('stream/duplicate', `Stream ${id} is already open`)
    this.#streams.set(id, { id, endpoint, args, ...handlers })
    this.#mux.sendText(JSON.stringify({ type: 'open', streamId: id, endpoint, payload: { args } }))
  }

  /** Send an uplink item to one logical stream. */
  sendStreamItem(id, value) {
    if (!this.#muxReady) throw new BridgeError('connection/not-connected', 'Remote stream socket is not connected')
    this.#mux.sendText(JSON.stringify({ type: 'item', streamId: id, value }))
  }

  /** Half-close one logical stream's uplink. */
  endStream(id) {
    if (!this.#muxReady) return
    this.#mux.sendText(JSON.stringify({ type: 'end', streamId: id }))
  }

  /** Cancel and forget one logical stream. */
  closeStream(id) {
    const stream = this.#streams.get(id)
    if (stream === undefined) return
    this.#streams.delete(id)
    if (this.#muxReady) {
      try { this.#mux.sendText(JSON.stringify({ type: 'cancel', streamId: id })) } catch { /* socket closing */ }
    }
  }

  /** Reopen every logical stream after a carrier reset. */
  reopenStreams() {
    const entries = [...this.#streams.values()]
    for (const stream of entries) {
      try {
        this.#mux.sendText(JSON.stringify({ type: 'open', streamId: stream.id, endpoint: stream.endpoint, payload: { args: stream.args } }))
      } catch (error) {
        stream.onError?.(new BridgeError('connection/transport', error instanceof Error ? error.message : String(error)))
      }
    }
  }

  /** Close the socket and all logical streams. */
  close() {
    for (const id of [...this.#streams.keys()]) this.closeStream(id)
    this.#streams.clear()
    this.#mux?.close()
    this.#mux = undefined
    this.#muxReady = false
  }

  #onMuxMessage(text) {
    let frame
    try {
      frame = JSON.parse(text)
    } catch {
      this.emit('error', new Error('Remote stream frame is not JSON'))
      return
    }
    if (typeof frame?.streamId !== 'string') return
    const stream = this.#streams.get(frame.streamId)
    if (stream === undefined) return
    if (frame.type === 'item') {
      stream.onItem?.(frame.value)
      return
    }
    if (frame.type === 'end') {
      this.#streams.delete(frame.streamId)
      stream.onEnd?.()
      return
    }
    if (frame.type === 'error') {
      this.#streams.delete(frame.streamId)
      const error = frame.error ?? {}
      stream.onError?.(new BridgeError(`host/${error.code ?? 'stream'}`, error.message ?? 'Remote stream failed', {
        ...(typeof error.details === 'object' && error.details !== null ? { details: error.details } : {}),
      }))
    }
  }
}
