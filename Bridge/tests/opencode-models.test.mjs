import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import {
  OPENCODE_GO_MODELS_URL,
  discoverOpenCodeGoModels,
  mapOpenCodeProtocol,
  parseOpenCodeGoCatalog,
} from '../src/opencode-models.mjs'
import { BridgeError } from '../src/protocol.mjs'

const fixture = JSON.parse(readFileSync(join(import.meta.dirname, 'fixtures/opencode-go-models.json'), 'utf8'))

test('OpenCode Go protocol keys map to DSH identifiers', () => {
  assert.equal(mapOpenCodeProtocol('chat-completions'), 'openai-completions')
  assert.equal(mapOpenCodeProtocol('responses'), 'openai-responses')
  assert.equal(mapOpenCodeProtocol('messages'), 'anthropic-messages')
  assert.equal(mapOpenCodeProtocol('generate-content'), 'google-generative-ai')
  assert.equal(mapOpenCodeProtocol('unknown'), undefined)
})

test('recorded OpenCode Go metadata preserves mixed protocols and limits', () => {
  const catalog = parseOpenCodeGoCatalog(fixture)
  assert.equal(catalog.models.length, 28)
  assert.equal(new Set(catalog.models.map(model => model.id)).size, 28)

  const claude = catalog.models.find(model => model.id === 'claude-haiku-5-5')
  assert.deepEqual(claude.protocols, ['anthropic-messages'])
  assert.equal(claude.contextWindow, 1000000)
  assert.equal(claude.maxTokens, 128000)
  assert.deepEqual(claude.inputModalities, ['text', 'image'])
  assert.deepEqual(claude.reasoningEfforts, ['low', 'medium', 'high', 'xhigh', 'max'])

  const grok = catalog.models.find(model => model.id === 'grok-4.7')
  assert.deepEqual(grok.protocols, ['openai-responses'])

  const gemini = catalog.models.find(model => model.id === 'gemini-4-argon')
  assert.deepEqual(gemini.protocols, ['google-generative-ai'])
  assert.ok(gemini.baseURLs.includes('https://opencode.ai/inference/go/google/v1beta'))

  const protocols = new Set(catalog.models.flatMap(model => model.protocols))
  assert.deepEqual(protocols, new Set([
    'openai-completions',
    'openai-responses',
    'anthropic-messages',
    'google-generative-ai',
  ]))
})

test('discovery identifies itself and sends no credential', async () => {
  let request
  const catalog = await discoverOpenCodeGoModels({
    fetchImpl: async (url, options) => {
      request = { url, options }
      return { ok: true, status: 200, text: async () => JSON.stringify(fixture) }
    },
  })
  assert.equal(request.url, OPENCODE_GO_MODELS_URL)
  assert.equal(request.options.headers['user-agent'], 'DeepSwift/1.0 (macOS)')
  assert.equal(request.options.headers['x-opencode-client'], 'deepswift')
  assert.equal(request.options.headers.authorization, undefined)
  assert.equal(catalog.models.length, 28)
})

test('HTTP failures are distinguishable from malformed metadata', async () => {
  await assert.rejects(
    discoverOpenCodeGoModels({
      fetchImpl: async () => ({ ok: false, status: 401, text: async () => '' }),
    }),
    error => error instanceof BridgeError && error.code === 'opencode/http' && /401/.test(error.message),
  )

  await assert.rejects(
    discoverOpenCodeGoModels({
      fetchImpl: async () => ({ ok: true, status: 200, text: async () => '<html>not json</html>' }),
    }),
    error => error instanceof BridgeError && error.code === 'opencode/malformed',
  )

  await assert.rejects(
    discoverOpenCodeGoModels({
      fetchImpl: async () => ({ ok: true, status: 200, text: async () => JSON.stringify({ data: 'wrong' }) }),
    }),
    error => error instanceof BridgeError && error.code === 'opencode/malformed',
  )
})

test('an empty catalog is a successful empty list', () => {
  const catalog = parseOpenCodeGoCatalog({ object: 'list', data: [] })
  assert.deepEqual(catalog.models, [])
  assert.deepEqual(catalog.skipped, [])
})

test('unsupported model types are skipped rather than failing the page', () => {
  const catalog = parseOpenCodeGoCatalog({
    data: [
      { id: 'chat', type: 'chat', name: 'Chat', api: { 'chat-completions': { base_url: 'https://example/v1' } } },
      { id: 'embedding', type: 'embedding', name: 'Embedding' },
    ],
  })
  assert.deepEqual(catalog.models.map(model => model.id), ['chat'])
  assert.deepEqual(catalog.skipped, [{ id: 'embedding', reason: 'unsupported type embedding' }])
})
