/**
 * Line-delimited JSON protocol shared with the Swift client.
 *
 * Inbound frames (Swift -> bridge):
 *   { id: string, method: string, params?: object }
 * Outbound frames (bridge -> Swift):
 *   { id: string, result: unknown }
 *   { id: string, error: { code: string, message: string, details?: object } }
 *   { event: string, data: unknown }
 *
 * This file only owns framing and validation; transport lives elsewhere.
 */

export const PROTOCOL_VERSION = 1

/** A protocol violation that should be reported to the caller, not crash the bridge. */
export class BridgeError extends Error {
  constructor(code, message, details = {}) {
    super(message)
    this.name = 'BridgeError'
    this.code = code
    this.details = details
  }
}

/** Parse one inbound line; returns null for blank lines. */
export function parseRequestLine(line) {
  const text = line.trim()
  if (text.length === 0) return null
  let value
  try {
    value = JSON.parse(text)
  } catch {
    throw new BridgeError('bridge/invalid-json', 'Request line is not valid JSON')
  }
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw new BridgeError('bridge/invalid-request', 'Request must be a JSON object')
  }
  if (typeof value.method !== 'string' || value.method.length === 0) {
    throw new BridgeError('bridge/invalid-request', 'Request is missing a method')
  }
  if (typeof value.id !== 'string' || value.id.length === 0) {
    throw new BridgeError('bridge/invalid-request', 'Request is missing an id')
  }
  if (value.params !== undefined && (typeof value.params !== 'object' || value.params === null || Array.isArray(value.params))) {
    throw new BridgeError('bridge/invalid-request', 'params must be an object')
  }
  return { id: value.id, method: value.method, params: value.params ?? {} }
}

/** Split a byte stream into complete newline-delimited frames. */
export class LineFramer {
  #buffer = ''

  /** Feed one UTF-8 chunk and return every complete line it completes. */
  push(chunk) {
    this.#buffer += chunk
    const lines = []
    let index = this.#buffer.indexOf('\n')
    while (index >= 0) {
      let line = this.#buffer.slice(0, index)
      if (line.endsWith('\r')) line = line.slice(0, -1)
      lines.push(line)
      this.#buffer = this.#buffer.slice(index + 1)
      index = this.#buffer.indexOf('\n')
    }
    return lines
  }

  /** Return a trailing unterminated line, if any. */
  flush() {
    const line = this.#buffer
    this.#buffer = ''
    return line.length > 0 ? [line] : []
  }
}
