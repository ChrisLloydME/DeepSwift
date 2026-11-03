import test from 'node:test'
import assert from 'node:assert/strict'
import { spawn } from 'node:child_process'
import { createInterface } from 'node:readline'
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { randomUUID } from 'node:crypto'
import { join } from 'node:path'

const root = process.cwd()
const dshBin = join(root, '.local/runtime/bridge/node_modules/@deepseek-ai/dsh/lib/bin.js')
const testRoot = join(root, '.local/tests')

function wait(ms) {
  return new Promise(resolve => setTimeout(resolve, ms))
}

async function startBridge(home, extraEnv = {}) {
  const child = spawn(process.execPath, ['Bridge/src/main.mjs'], {
    env: {
      PATH: process.env.PATH,
      HOME: process.env.HOME,
      TMPDIR: process.env.TMPDIR,
      LANG: process.env.LANG,
      DEEPSWIFT_NODE_BIN: process.execPath,
      DEEPSWIFT_DSH_BIN: dshBin,
      DEEPSWIFT_DSH_HOME: home,
      ...extraEnv,
    },
    stdio: ['pipe', 'pipe', 'pipe'],
  })
  const lines = createInterface({ input: child.stdout })
  const pending = new Map()
  const eventWaiters = new Map()
  let nextId = 1

  lines.on('line', line => {
    const frame = JSON.parse(line)
    if (frame.event) {
      const waiters = eventWaiters.get(frame.event)
      if (waiters !== undefined) {
        eventWaiters.delete(frame.event)
        for (const resolve of waiters) resolve(frame.data)
      }
      return
    }
    const entry = pending.get(frame.id)
    if (entry === undefined) return
    pending.delete(frame.id)
    if (frame.error) entry.reject(Object.assign(new Error(frame.error.message), frame.error))
    else entry.resolve(frame.result)
  })

  const request = (method, params = {}) => new Promise((resolve, reject) => {
    const id = String(nextId++)
    pending.set(id, { resolve, reject })
    child.stdin.write(JSON.stringify({ id, method, params }) + '\n')
  })

  const waitForEvent = (event, timeoutMs = 30_000) => {
    if (eventWaiters.has(event)) {
      return new Promise(resolve => eventWaiters.get(event).push(resolve))
    }
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        eventWaiters.delete(event)
        reject(new Error(`Timed out waiting for ${event}`))
      }, timeoutMs)
      eventWaiters.set(event, [data => {
        clearTimeout(timer)
        resolve(data)
      }])
    })
  }

  child.stderr.on('data', () => {
    // The bridge reports host failures through protocol events; stderr is
    // retained by the app in production and deliberately not echoed here.
  })

  return { child, request, waitForEvent }
}

test('opted-in OpenCode credentials reach the isolated Host provider', { timeout: 60_000 }, async t => {
  if (!existsSync(dshBin)) {
    t.skip('Pinned DSH development runtime is not installed')
    return
  }
  mkdirSync(testRoot, { recursive: true })
  const home = mkdtempSync(join(testRoot, 'opencode-env-'))
  const bridge = await startBridge(home, {
    DEEPSWIFT_ALLOW_PROVIDER_ENV: '1',
    OPENCODE_GO_API_KEY: 'test-only-opencode-key',
  })
  try {
    await bridge.waitForEvent('host.connected')
    const description = await bridge.request('host.call', {
      namespace: 'settings', method: 'describe', args: {},
    })
    const pi = description.namespaces.find(namespace => namespace.ns === 'llm-pi-ai')
    await bridge.request('host.call', {
      namespace: 'settings',
      method: 'mutate',
      args: {
        ns: 'llm-pi-ai',
        expectedRevision: pi.revision,
        ops: [{
          op: 'set',
          path: ['providers', 'opencode-go'],
          value: { apiKeyEnv: 'OPENCODE_GO_API_KEY', displayName: 'opencode-go' },
        }],
      },
    })
    const catalog = await bridge.request('host.call', {
      namespace: 'session', method: 'modelCatalog', args: {},
    })
    const group = catalog.groups.find(item => item.id === 'opencode-go')
    assert.ok(group, 'OpenCode Go was absent from the catalog')
    assert.ok(group.models.length > 0, 'OpenCode Go resolved no models from the passed credential')
    assert.ok(!JSON.stringify(catalog).includes('test-only-opencode-key'))
    await bridge.request('shutdown')
  } finally {
    if (bridge.child.exitCode === null) bridge.child.kill('SIGTERM')
    await wait(250)
    rmSync(home, { recursive: true, force: true })
  }
})

test('provider settings and redacted credentials survive an isolated Host restart', { timeout: 120_000 }, async t => {
  if (!existsSync(dshBin)) {
    t.skip('Pinned DSH development runtime is not installed')
    return
  }

  mkdirSync(testRoot, { recursive: true })
  const home = mkdtempSync(join(testRoot, 'provider-'))
  const provider = `test-gateway-${randomUUID().slice(0, 8)}`
  const reference = `${provider.replaceAll('-', '_').toUpperCase()}_API_KEY`
  const secret = `sk-test-${randomUUID()}`
  const bridge = await startBridge(home)

  try {
    await bridge.waitForEvent('host.connected')
    const initial = await bridge.request('host.call', {
      namespace: 'settings', method: 'describe', args: {},
    })
    const pi = initial.namespaces.find(namespace => namespace.ns === 'llm-pi-ai')
    assert.ok(pi, 'llm-pi-ai settings namespace is missing')

    const before = await bridge.request('host.call', {
      namespace: 'settings',
      method: 'mutate',
      args: {
        ns: 'llm-pi-ai',
        expectedRevision: pi.revision,
        ops: [{
          op: 'set',
          path: ['providers', provider],
          value: {
            displayName: 'Persistence Test Gateway',
            api: 'openai-completions',
            baseURL: 'http://127.0.0.1:9/v1',
            apiKeyEnv: reference,
            models: [{ id: 'test-chat', name: 'Test Chat', contextWindow: 32768, maxTokens: 4096, input: ['text'] }],
          },
        }],
      },
    })
    assert.equal(before.value.providers[provider].displayName, 'Persistence Test Gateway')
    assert.ok(!JSON.stringify(before).includes(secret), 'settings response leaked the secret')

    await bridge.request('host.call', {
      namespace: 'credentials', method: 'set', args: { ref: reference, value: secret },
    })
    const redacted = await bridge.request('host.call', {
      namespace: 'credentials', method: 'describe', args: { refs: [reference] },
    })
    assert.equal(redacted[reference].configured, true)
    assert.equal(redacted[reference].source, 'file')
    assert.equal(redacted[reference].writable, true)
    assert.ok(!JSON.stringify(redacted).includes(secret), 'credential description leaked the secret')

    const reconnected = bridge.waitForEvent('host.connected')
    await bridge.request('runtime.restart')
    await reconnected

    const after = await bridge.request('host.call', {
      namespace: 'settings', method: 'describe', args: {},
    })
    const persisted = after.namespaces
      .find(namespace => namespace.ns === 'llm-pi-ai')
      .value.providers[provider]
    assert.equal(persisted.displayName, 'Persistence Test Gateway')
    assert.equal(persisted.apiKeyEnv, reference)
    assert.equal(persisted.models[0].id, 'test-chat')

    const credentialAfter = await bridge.request('host.call', {
      namespace: 'credentials', method: 'describe', args: { refs: [reference] },
    })
    assert.equal(credentialAfter[reference].configured, true)

    const piAfter = after.namespaces.find(namespace => namespace.ns === 'llm-pi-ai')
    await bridge.request('host.call', {
      namespace: 'settings',
      method: 'mutate',
      args: {
        ns: 'llm-pi-ai',
        expectedRevision: piAfter.revision,
        ops: [{ op: 'unset', path: ['providers', provider] }],
      },
    })
    await bridge.request('host.call', {
      namespace: 'credentials', method: 'unset', args: { ref: reference },
    })

    const workspacePath = mkdtempSync(join(testRoot, 'workspace-'))
    writeFileSync(join(workspacePath, 'hello.txt'), 'hello from the isolated workspace')
    const workspace = await bridge.request('host.call', {
      namespace: 'workspace', method: 'create', args: { request: { path: workspacePath } },
    })
    const session = await bridge.request('host.call', {
      namespace: 'session', method: 'create', args: { request: { workspaceId: workspace.workspace.workspaceId } },
    })
    const bytes = await bridge.request('workspace.readBytes', {
      sessionId: session.sessionId,
      path: 'hello.txt',
    })
    assert.equal(bytes.absolutePath, join(workspacePath, 'hello.txt'))
    assert.equal(bytes.eof, true)
    assert.equal(Buffer.from(bytes.dataBase64, 'base64').toString('utf8'), 'hello from the isolated workspace')

    await bridge.request('shutdown')
    await wait(500)

    const bridgeLogPath = join(home, 'logs/bridge.log')
    if (existsSync(bridgeLogPath)) {
      assert.ok(!readFileSync(bridgeLogPath, 'utf8').includes(secret), 'bridge log leaked the secret')
    }
  } finally {
    if (bridge.child.exitCode === null) bridge.child.kill('SIGTERM')
    await wait(250)
    rmSync(home, { recursive: true, force: true })
  }
})
