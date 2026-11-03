import { BridgeError } from './protocol.mjs'

export const OPENCODE_GO_MODELS_URL = 'https://opencode.ai/inference/go/v1/models'

const PROTOCOL_MAP = Object.freeze({
  'chat-completions': 'openai-completions',
  responses: 'openai-responses',
  messages: 'anthropic-messages',
  'generate-content': 'google-generative-ai',
})

/** Map an OpenCode wire-protocol key to the identifier DSH uses. */
export function mapOpenCodeProtocol(key) {
  return PROTOCOL_MAP[key]
}

function inputModalities(value) {
  const inputs = Array.isArray(value) ? value : []
  const result = new Set()
  for (const input of inputs) {
    if (input === 'text') result.add('text')
    else if (typeof input === 'string' && input.startsWith('image/')) result.add('image')
  }
  if (result.size === 0) result.add('text')
  return [...result]
}

function optionalPositiveInteger(value) {
  return Number.isSafeInteger(value) && value > 0 ? value : undefined
}

/**
 * Decode the documented OpenCode Go `/v1/models` response.
 * The endpoint is public metadata; no credential is sent by this adapter.
 */
export function parseOpenCodeGoCatalog(payload, { source = OPENCODE_GO_MODELS_URL } = {}) {
  if (typeof payload !== 'object' || payload === null || Array.isArray(payload)) {
    throw new BridgeError('opencode/malformed', 'OpenCode Go returned a non-object metadata response')
  }
  if (!Array.isArray(payload.data)) {
    throw new BridgeError('opencode/malformed', 'OpenCode Go metadata has no data array')
  }

  const models = []
  const skipped = []
  for (const entry of payload.data) {
    if (typeof entry !== 'object' || entry === null || Array.isArray(entry)) {
      throw new BridgeError('opencode/malformed', 'OpenCode Go metadata contains a malformed model entry')
    }
    if (entry.type !== undefined && entry.type !== 'chat') {
      skipped.push({ id: typeof entry.id === 'string' ? entry.id : 'unknown', reason: `unsupported type ${String(entry.type)}` })
      continue
    }
    if (typeof entry.id !== 'string' || entry.id.length === 0) {
      throw new BridgeError('opencode/malformed', 'OpenCode Go metadata contains a model without an id')
    }
    const api = typeof entry.api === 'object' && entry.api !== null && !Array.isArray(entry.api) ? entry.api : {}
    const apiKeys = Object.keys(api)
    const protocols = [...new Set(apiKeys.map(mapOpenCodeProtocol).filter(Boolean))]
    const baseURLs = [...new Set(apiKeys.map(key => api[key]?.base_url).filter(value => typeof value === 'string' && value.length > 0))]
    const reasoning = entry.capabilities?.reasoning
    const efforts = Array.isArray(reasoning?.effort) ? reasoning.effort.filter(value => typeof value === 'string') : []
    models.push({
      id: entry.id,
      name: typeof entry.name === 'string' && entry.name.length > 0 ? entry.name : entry.id,
      protocols,
      baseURLs,
      contextWindow: optionalPositiveInteger(entry.limit?.context),
      maxTokens: optionalPositiveInteger(entry.limit?.output),
      inputModalities: inputModalities(entry.modalities?.input),
      reasoningEfforts: efforts,
      skipped: protocols.length === 0 ? apiKeys : undefined,
    })
  }

  return {
    source,
    fetchedAt: new Date().toISOString(),
    models,
    skipped,
  }
}

/** Fetch and decode the live OpenCode Go catalog. */
export async function discoverOpenCodeGoModels({ fetchImpl = globalThis.fetch, signal, timeoutMs = 20_000 } = {}) {
  if (typeof fetchImpl !== 'function') {
    throw new BridgeError('opencode/network', 'No fetch implementation is available')
  }
  const timeout = AbortSignal.timeout(timeoutMs)
  const combined = signal === undefined ? timeout : AbortSignal.any([signal, timeout])
  let response
  try {
    response = await fetchImpl(OPENCODE_GO_MODELS_URL, {
      method: 'GET',
      redirect: 'follow',
      headers: {
        accept: 'application/json',
        'user-agent': 'DeepSwift/1.0 (macOS)',
        'x-opencode-client': 'deepswift',
      },
      signal: combined,
    })
  } catch (error) {
    if (signal?.aborted) throw new BridgeError('opencode/aborted', 'OpenCode Go discovery was cancelled')
    throw new BridgeError('opencode/network', `Could not reach ${OPENCODE_GO_MODELS_URL}`, {
      cause: error instanceof Error ? error.message : String(error),
    })
  }

  if (!response.ok) {
    const suffix = response.status === 401 || response.status === 403 ? '; authentication was rejected' : ''
    throw new BridgeError(
      'opencode/http',
      `${OPENCODE_GO_MODELS_URL} answered ${response.status}${suffix}`,
      { status: response.status, url: OPENCODE_GO_MODELS_URL },
    )
  }

  let text
  try {
    text = await response.text()
  } catch (error) {
    throw new BridgeError('opencode/network', 'Could not read the OpenCode Go metadata response', {
      cause: error instanceof Error ? error.message : String(error),
    })
  }
  if (text.length > 4_000_000) {
    throw new BridgeError('opencode/malformed', 'OpenCode Go metadata response is unexpectedly large')
  }
  let payload
  try {
    payload = JSON.parse(text)
  } catch (error) {
    throw new BridgeError('opencode/malformed', 'OpenCode Go metadata is not valid JSON', {
      cause: error instanceof Error ? error.message : String(error),
    })
  }
  return parseOpenCodeGoCatalog(payload)
}
