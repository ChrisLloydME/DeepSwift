/**
 * Owns the isolated DSH Host subprocess.
 *
 * Isolation contract:
 * - DSH_HOME must be supplied explicitly by the application and is never
 *   defaulted to the user's existing DSH home.
 * - Only an allowlisted environment reaches the Host. Ambient DSH_* variables
 *   are removed so a developer shell cannot redirect the runtime.
 * - The Host binds loopback on an OS-assigned port.
 * - Only the exact child pid is signalled; no process groups or global names.
 */

import { spawn } from 'node:child_process'
import { EventEmitter } from 'node:events'
import { createWriteStream, existsSync, mkdirSync, realpathSync, statSync } from 'node:fs'
import { homedir } from 'node:os'
import { isAbsolute, join, resolve } from 'node:path'
import { createInterface } from 'node:readline'

const READY_PATTERN = /dsh web:\s+(https?:\/\/\S+)/
const DEFAULT_READY_TIMEOUT_MS = 45_000
const DEFAULT_STOP_GRACE_MS = 5_000

/** Reject a home directory that would touch the user's existing DSH state. */
export function assertIsolatedHome(home, { userHome = homedir() } = {}) {
  if (typeof home !== 'string' || home.length === 0 || !isAbsolute(home)) {
    throw new Error('DSH_HOME must be an absolute, explicit directory')
  }
  const resolved = resolve(home)
  const forbidden = [join(userHome, '.dsh'), join(userHome, '.config', 'dsh'), join(userHome, 'Library', 'Application Support', 'dsh')]
  for (const candidate of forbidden) {
    if (resolved === candidate) throw new Error(`DSH_HOME ${resolved} is the user's existing DSH home; refusing to reuse it`)
  }
  if (existsSync(resolved)) {
    const real = realpathSync(resolved)
    for (const candidate of forbidden) {
      if (real === candidate) throw new Error(`DSH_HOME resolves to the user's existing DSH home; refusing to reuse it`)
    }
    if (!statSync(real).isDirectory()) throw new Error('DSH_HOME exists and is not a directory')
  } else {
    mkdirSync(resolved, { recursive: true, mode: 0o700 })
  }
  return resolved
}

/**
 * Build a minimal child environment.
 * DSH_* is never inherited; provider credentials are passed only when the
 * caller opted in through DEEPSWIFT_ALLOW_PROVIDER_ENV=1.
 */
export function buildHostEnvironment({ home, baseEnv = process.env, allowProviderEnv = false }) {
  const keep = ['PATH', 'HOME', 'TMPDIR', 'TMP', 'TEMP', 'LANG', 'LC_ALL', 'LC_CTYPE', 'TERM', 'TZ', 'USER', 'LOGNAME', 'SHELL']
  const env = {}
  for (const key of keep) {
    const value = baseEnv[key]
    if (typeof value === 'string') env[key] = value
  }
  if (allowProviderEnv) {
    for (const [key, value] of Object.entries(baseEnv)) {
      if (typeof value === 'string' && /^(DEEPSEEK|OPENAI|ANTHROPIC|OPENCODE)_[A-Z0-9_]+$/.test(key)) env[key] = value
    }
  }
  env.DSH_HOME = home
  // Keep shared agent instructions and skills out of the user's ~/.agents.
  env.DSH_AGENTS_HOME = join(home, 'agents')
  env.NO_COLOR = '1'
  env.npm_config_cache = join(home, 'cache', 'npm')
  env.npm_config_update_notifier = 'false'
  return env
}

/** One running Host generation. */
export class HostRuntime extends EventEmitter {
  #child
  #ready
  #stderrTail = []
  #logStream
  #stopping = false
  #exited = false

  /**
   * @param {object} options
   * @param {string} options.nodeBin - absolute Node executable.
   * @param {string} options.hostBin - absolute @deepseek-ai/dsh bin.js.
   * @param {string} options.home - isolated DSH home.
   * @param {string} [options.cwd] - process working directory.
   * @param {boolean} [options.allowProviderEnv] - pass provider API key variables.
   */
  constructor(options) {
    super()
    this.options = options
    this.home = assertIsolatedHome(options.home)
  }

  /** The retained stderr tail, newest last. */
  get stderrTail() {
    return this.#stderrTail.join('')
  }

  /** Start the Host and resolve once it prints its authenticated URL. */
  async start({ timeoutMs = DEFAULT_READY_TIMEOUT_MS } = {}) {
    if (this.#child !== undefined) throw new Error('Host runtime is already started')
    mkdirSync(join(this.home, 'logs'), { recursive: true, mode: 0o700 })
    const logPath = join(this.home, 'logs', 'host.log')
    this.#logStream = createWriteStream(logPath, { flags: 'a', mode: 0o600 })

    const env = buildHostEnvironment({
      home: this.home,
      baseEnv: process.env,
      allowProviderEnv: this.options.allowProviderEnv === true,
    })
    const patches = Array.isArray(this.options.patches) ? this.options.patches : []
    const args = [
      this.options.hostBin,
      '--profile', 'web',
      ...patches.flatMap(path => ['--patch', path]),
      '--no-open', '--host', '127.0.0.1', '--port', '0',
    ]
    const child = spawn(this.options.nodeBin, args, {
      cwd: this.options.cwd ?? this.home,
      env,
      stdio: ['ignore', 'pipe', 'pipe'],
      detached: false,
      windowsHide: true,
    })
    this.#child = child
    this.#ready = new Promise((resolve, reject) => {
      let settled = false
      const timer = setTimeout(() => {
        if (settled) return
        settled = true
        reject(new Error(`DSH Host did not become ready within ${timeoutMs} ms.${this.#stderrTail.length > 0 ? `\n${this.stderrTail}` : ''}`))
      }, timeoutMs)
      timer.unref?.()

      const stdout = createInterface({ input: child.stdout })
      stdout.on('line', (line) => {
        this.#log(`stdout: ${line}\n`)
        const match = READY_PATTERN.exec(line)
        if (match !== null && !settled) {
          settled = true
          clearTimeout(timer)
          resolve(match[1])
        }
      })
      const stderr = createInterface({ input: child.stderr })
      stderr.on('line', (line) => {
        this.#remember(`stderr: ${line}\n`)
        this.#log(`stderr: ${line}\n`)
        this.emit('log', line)
      })
      child.on('error', (error) => {
        if (settled) return
        settled = true
        clearTimeout(timer)
        reject(error)
      })
      child.on('exit', (code, signal) => {
        this.#exited = true
        const detail = this.stderrTail.length > 0 ? `\n${this.stderrTail}` : ''
        this.#log(`exit: code=${String(code)} signal=${String(signal)}\n`)
        this.emit('exit', { code, signal, stderr: this.stderrTail })
        if (!settled) {
          settled = true
          clearTimeout(timer)
          reject(new Error(`DSH Host exited before it became ready (code ${String(code)}, signal ${String(signal)}).${detail}`))
        }
      })
    })
    const url = await this.#ready
    this.emit('ready', url)
    return url
  }

  /** Stop only this child, escalating after the grace period. */
  async stop({ graceMs = DEFAULT_STOP_GRACE_MS } = {}) {
    const child = this.#child
    if (child === undefined || this.#exited) {
      this.#logStream?.end()
      return
    }
    this.#stopping = true
    const exited = new Promise((resolve) => child.once('exit', resolve))
    child.kill('SIGTERM')
    const timer = setTimeout(() => {
      if (!this.#exited) child.kill('SIGKILL')
    }, graceMs)
    timer.unref?.()
    await Promise.race([exited, new Promise((resolve) => setTimeout(resolve, graceMs + 2_000))])
    clearTimeout(timer)
    this.#stopping = false
    this.#logStream?.end()
  }

  get isRunning() {
    return this.#child !== undefined && !this.#exited
  }

  get childPid() {
    return this.#child?.pid
  }

  get isStopping() {
    return this.#stopping
  }

  #remember(text) {
    this.#stderrTail.push(text)
    while (this.#stderrTail.join('').length > 16_000) this.#stderrTail.shift()
  }

  #log(text) {
    this.#logStream?.write(text)
  }
}
