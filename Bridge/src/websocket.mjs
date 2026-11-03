/**
 * Minimal RFC 6455 text WebSocket client built on Node's http module.
 *
 * The bridge speaks exactly one protocol to the DSH Host: JSON text frames on
 * a loopback socket authenticated by the connect cookie. Avoiding a third-party
 * WebSocket implementation keeps the bridge dependency-free while remaining a
 * standard client; binary frames, extensions, and subprotocols are refused.
 */

import { EventEmitter } from 'node:events'
import { createHash, randomBytes } from 'node:crypto'
import http from 'node:http'
import https from 'node:https'

const GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'
const MAX_MESSAGE_BYTES = 64 * 1024 * 1024
const PING_INTERVAL_MS = 20_000
const PONG_DEADLINE_MS = 45_000

/** One connected text WebSocket. */
export class WebSocketClient extends EventEmitter {
  #socket
  #buffer = Buffer.alloc(0)
  #fragments = []
  #fragmentBytes = 0
  #pingTimer
  #lastPong = Date.now()
  #closed = false
  #closing = false
  #closeSent = false

  /**
   * Open a WebSocket and resolve after the 101 upgrade.
   * @param {string} url - ws:// or wss:// URL.
   * @param {Record<string,string>} headers - extra request headers, including Cookie.
   */
  static connect(url, headers = {}) {
    const client = new WebSocketClient()
    return client.#open(url, headers).then(() => client)
  }

  #open(url, headers) {
    return new Promise((resolve, reject) => {
      const target = new URL(url)
      const secure = target.protocol === 'wss:'
      if (!secure && target.protocol !== 'ws:') {
        reject(new Error(`Unsupported WebSocket protocol ${target.protocol}`))
        return
      }
      const key = randomBytes(16).toString('base64')
      const request = (secure ? https : http).request({
        protocol: target.protocol === 'wss:' ? 'https:' : 'http:',
        hostname: target.hostname,
        port: target.port,
        path: `${target.pathname}${target.search}`,
        method: 'GET',
        headers: {
          Connection: 'Upgrade',
          Upgrade: 'websocket',
          'Sec-WebSocket-Version': '13',
          'Sec-WebSocket-Key': key,
          ...headers,
        },
      })
      request.setTimeout(15_000, () => request.destroy(new Error('WebSocket upgrade timed out')))
      request.on('error', reject)
      request.on('response', (response) => {
        response.resume()
        reject(new Error(`WebSocket upgrade refused with HTTP ${response.statusCode}`))
      })
      request.on('upgrade', (response, socket, head) => {
        const accept = response.headers['sec-websocket-accept']
        const expected = createHash('sha1').update(key + GUID).digest('base64')
        if (accept !== expected) {
          socket.destroy()
          reject(new Error('WebSocket upgrade returned an invalid accept key'))
          return
        }
        this.#socket = socket
        socket.setNoDelay(true)
        socket.on('data', (chunk) => this.#receive(chunk))
        socket.on('error', (error) => this.#fail(error))
        socket.on('close', () => {
          if (this.#closed) return
          this.#closed = true
          clearInterval(this.#pingTimer)
          if (this.#closing) this.emit('close', { code: 1000, reason: 'closed' })
          else this.#fail(new Error('WebSocket closed'))
        })
        this.#lastPong = Date.now()
        this.#pingTimer = setInterval(() => {
          if (this.#closed) return
          if (Date.now() - this.#lastPong > PONG_DEADLINE_MS) {
            this.terminate()
            return
          }
          this.#sendFrame(0x9, Buffer.alloc(0))
        }, PING_INTERVAL_MS)
        this.#pingTimer.unref?.()
        if (head.length > 0) this.#receive(head)
        resolve()
      })
      request.end()
    })
  }

  get isOpen() {
    return this.#socket !== undefined && !this.#closed
  }

  /** Send one text message. */
  sendText(text) {
    if (!this.isOpen) throw new Error('WebSocket is not open')
    this.#sendFrame(0x1, Buffer.from(text, 'utf8'))
  }

  /** Close politely; the peer may already be gone. */
  close() {
    if (this.#closed) return
    this.#closing = true
    this.#closeSent = true
    try { this.#sendFrame(0x8, Buffer.from([0x03, 0xe8])) } catch { /* socket teardown below */ }
    this.#socket?.end()
    setTimeout(() => this.terminate(), 500).unref?.()
  }

  /** Destroy the transport without a closing handshake. */
  terminate() {
    if (this.#closed) return
    this.#closed = true
    clearInterval(this.#pingTimer)
    this.#socket?.destroy()
    this.emit('close', { code: 1006, reason: 'terminated' })
  }

  #fail(error) {
    if (this.#closed) return
    this.#closed = true
    clearInterval(this.#pingTimer)
    this.#socket?.destroy()
    this.emit('error', error)
    this.emit('close', { code: 1006, reason: error.message })
  }

  #receive(chunk) {
    this.#buffer = Buffer.concat([this.#buffer, chunk])
    while (true) {
      if (this.#buffer.length < 2) return
      const first = this.#buffer[0]
      const second = this.#buffer[1]
      const fin = (first & 0x80) !== 0
      const opcode = first & 0x0f
      const masked = (second & 0x80) !== 0
      let length = second & 0x7f
      let offset = 2
      if (length === 126) {
        if (this.#buffer.length < 4) return
        length = this.#buffer.readUInt16BE(2)
        offset = 4
      } else if (length === 127) {
        if (this.#buffer.length < 10) return
        const high = this.#buffer.readUInt32BE(2)
        const low = this.#buffer.readUInt32BE(6)
        if (high !== 0) { this.#protocolError('Frame too large'); return }
        length = low
        offset = 10
      }
      if (length > MAX_MESSAGE_BYTES) { this.#protocolError('Frame exceeds message limit'); return }
      const maskLength = masked ? 4 : 0
      if (this.#buffer.length < offset + maskLength + length) return
      let payload = this.#buffer.subarray(offset + maskLength, offset + maskLength + length)
      if (masked) {
        const mask = this.#buffer.subarray(offset, offset + 4)
        payload = Buffer.from(payload)
        for (let i = 0; i < payload.length; i += 1) payload[i] ^= mask[i % 4]
      }
      this.#buffer = this.#buffer.subarray(offset + maskLength + length)

      if (opcode === 0x8) {
        const code = payload.length >= 2 ? payload.readUInt16BE(0) : 1005
        const reason = payload.length > 2 ? payload.subarray(2).toString('utf8') : ''
        this.#closed = true
        clearInterval(this.#pingTimer)
        if (!this.#closeSent) {
          try { this.#sendFrame(0x8, payload.subarray(0, 2)) } catch { /* peer gone */ }
        }
        this.#socket?.end()
        this.emit('close', { code, reason })
        return
      }
      if (opcode === 0x9) {
        this.#sendFrame(0xa, payload)
        continue
      }
      if (opcode === 0xa) {
        this.#lastPong = Date.now()
        continue
      }
      if (opcode === 0x2) { this.#protocolError('Binary frames are not supported'); return }
      if (opcode !== 0x0 && opcode !== 0x1) { this.#protocolError(`Unsupported opcode ${opcode}`); return }

      if (opcode === 0x1) {
        this.#fragments = []
        this.#fragmentBytes = 0
      }
      this.#fragments.push(Buffer.from(payload))
      this.#fragmentBytes += payload.length
      if (this.#fragmentBytes > MAX_MESSAGE_BYTES) { this.#protocolError('Message exceeds limit'); return }
      if (!fin) continue
      const message = Buffer.concat(this.#fragments).toString('utf8')
      this.#fragments = []
      this.#fragmentBytes = 0
      this.emit('message', message)
    }
  }

  #protocolError(message) {
    try { this.#sendFrame(0x8, Buffer.from([0x03, 0xea])) } catch { /* peer gone */ }
    this.#fail(new Error(message))
  }

  #sendFrame(opcode, payload) {
    const socket = this.#socket
    if (socket === undefined || socket.destroyed) throw new Error('WebSocket is not open')
    const length = payload.length
    let header
    if (length < 126) {
      header = Buffer.alloc(2)
      header[1] = 0x80 | length
    } else if (length <= 0xffff) {
      header = Buffer.alloc(4)
      header[1] = 0x80 | 126
      header.writeUInt16BE(length, 2)
    } else {
      header = Buffer.alloc(10)
      header[1] = 0x80 | 127
      header.writeUInt32BE(0, 2)
      header.writeUInt32BE(length, 6)
    }
    header[0] = 0x80 | opcode
    const mask = randomBytes(4)
    const masked = Buffer.from(payload)
    for (let i = 0; i < masked.length; i += 1) masked[i] ^= mask[i % 4]
    socket.write(Buffer.concat([header, mask, masked]))
  }
}
