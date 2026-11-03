import test from 'node:test'
import assert from 'node:assert/strict'
import http from 'node:http'
import { createHash } from 'node:crypto'
import { WebSocketClient } from '../src/websocket.mjs'

const GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'

function encodeServerText(text) {
  const payload = Buffer.from(text, 'utf8')
  let header
  if (payload.length < 126) {
    header = Buffer.from([0x81, payload.length])
  } else {
    header = Buffer.alloc(4)
    header[0] = 0x81
    header[1] = 126
    header.writeUInt16BE(payload.length, 2)
  }
  return Buffer.concat([header, payload])
}

function decodeClientFrames(buffer) {
  const frames = []
  let offset = 0
  while (offset + 2 <= buffer.length) {
    const first = buffer[offset]
    const second = buffer[offset + 1]
    let length = second & 0x7f
    let header = 2
    if (length === 126) {
      if (offset + 4 > buffer.length) break
      length = buffer.readUInt16BE(offset + 2)
      header = 4
    } else if (length === 127) {
      if (offset + 10 > buffer.length) break
      length = buffer.readUInt32BE(offset + 6)
      header = 10
    }
    const masked = (second & 0x80) !== 0
    const maskLength = masked ? 4 : 0
    if (offset + header + maskLength + length > buffer.length) break
    let payload = Buffer.from(buffer.subarray(offset + header + maskLength, offset + header + maskLength + length))
    if (masked) {
      const mask = buffer.subarray(offset + header, offset + header + 4)
      for (let i = 0; i < payload.length; i += 1) payload[i] ^= mask[i % 4]
    }
    frames.push({ opcode: first & 0x0f, payload })
    offset += header + maskLength + length
  }
  return { frames, rest: buffer.subarray(offset) }
}

test('WebSocket client upgrades, sends masked text, and receives text frames', async () => {
  let receivedCookie
  let clientFrame
  const server = http.createServer()
  server.on('upgrade', (request, socket) => {
    receivedCookie = request.headers.cookie
    const key = request.headers['sec-websocket-key']
    const accept = createHash('sha1').update(key + GUID).digest('base64')
    socket.write(
      'HTTP/1.1 101 Switching Protocols\r\n'
      + 'Upgrade: websocket\r\n'
      + 'Connection: Upgrade\r\n'
      + `Sec-WebSocket-Accept: ${accept}\r\n\r\n`
    )
    let buffer = Buffer.alloc(0)
    socket.on('data', (chunk) => {
      buffer = Buffer.concat([buffer, chunk])
      const decoded = decodeClientFrames(buffer)
      buffer = decoded.rest
      for (const frame of decoded.frames) {
        if (frame.opcode === 0x1) {
          clientFrame = frame.payload.toString('utf8')
          socket.write(encodeServerText(`echo:${clientFrame}`))
        }
        if (frame.opcode === 0x8) socket.end()
      }
    })
  })
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve))
  const { port } = server.address()
  const client = await WebSocketClient.connect(`ws://127.0.0.1:${port}/api/remote.mux`, { cookie: 'session=abc' })
  const message = new Promise((resolve) => client.once('message', resolve))
  client.sendText('hello')
  assert.equal(await message, 'echo:hello')
  assert.equal(receivedCookie, 'session=abc')
  assert.equal(clientFrame, 'hello')
  client.close()
  await new Promise((resolve) => server.close(resolve))
})
