import test from 'node:test'
import assert from 'node:assert/strict'
import { BridgeError, LineFramer, parseRequestLine } from '../src/protocol.mjs'

test('LineFramer keeps partial UTF-8 frames until their newline arrives', () => {
  const framer = new LineFramer()
  assert.deepEqual(framer.push('{"id":"1"'), [])
  assert.deepEqual(framer.push(',"method":"a"}\n{"id":"2"'), ['{"id":"1","method":"a"}'])
  assert.deepEqual(framer.push(',"method":"b"}\r\n'), ['{"id":"2","method":"b"}'])
  assert.deepEqual(framer.flush(), [])
})

test('parseRequestLine validates the bridge request shape', () => {
  assert.deepEqual(parseRequestLine('  '), null)
  assert.deepEqual(parseRequestLine('{"id":"1","method":"runtime.status"}'), {
    id: '1',
    method: 'runtime.status',
    params: {},
  })
  assert.throws(() => parseRequestLine('not json'), BridgeError)
  assert.throws(() => parseRequestLine('{"method":"x"}'), /missing an id/)
  assert.throws(() => parseRequestLine('{"id":"1"}'), /missing a method/)
  assert.throws(() => parseRequestLine('{"id":"1","method":"x","params":[]}'), /params must be an object/)
})

test('BridgeError keeps its code and details', () => {
  const error = new BridgeError('host/denied', 'Denied', { details: { reason: 'policy' } })
  assert.equal(error.code, 'host/denied')
  assert.equal(error.message, 'Denied')
  assert.deepEqual(error.details, { details: { reason: 'policy' } })
})
