import test from 'node:test'
import assert from 'node:assert/strict'
import { mkdtempSync, mkdirSync, rmSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'
import { assertIsolatedHome, buildHostEnvironment } from '../src/host-process.mjs'

const testRoot = join(process.cwd(), '.local', 'tests')

function scratch() {
  mkdirSync(testRoot, { recursive: true })
  return mkdtempSync(join(testRoot, 'home-'))
}

test('isolated home must be absolute and explicit', () => {
  assert.throws(() => assertIsolatedHome('relative/path'), /absolute, explicit/)
  assert.throws(() => assertIsolatedHome(''), /absolute, explicit/)
})

test("isolated home refuses the user's existing DSH directories", () => {
  assert.throws(() => assertIsolatedHome(join(homedir(), '.dsh')), /existing DSH home/)
  assert.throws(
    () => assertIsolatedHome(join(homedir(), 'Library', 'Application Support', 'dsh')),
    /existing DSH home/
  )
})

test('isolated home is created and returned', () => {
  const base = scratch()
  try {
    const home = join(base, 'profile')
    assert.equal(assertIsolatedHome(home), home)
  } finally {
    rmSync(base, { recursive: true, force: true })
  }
})

test('host environment drops ambient DSH variables and provider secrets by default', () => {
  const env = buildHostEnvironment({
    home: '/tmp/isolated',
    baseEnv: {
      PATH: '/usr/bin',
      HOME: '/Users/example',
      DSH_HOME: '/Users/example/.dsh',
      DSH_PROFILE: 'user-profile',
      DEEPSEEK_API_KEY: 'secret',
    },
  })
  assert.equal(env.DSH_HOME, '/tmp/isolated')
  assert.equal(env.DSH_PROFILE, undefined)
  assert.equal(env.DEEPSEEK_API_KEY, undefined)
  assert.equal(env.npm_config_cache, '/tmp/isolated/cache/npm')
  assert.equal(env.PATH, '/usr/bin')
})

test('provider environment is passed only with explicit opt-in', () => {
  const env = buildHostEnvironment({
    home: '/tmp/isolated',
    baseEnv: {
      PATH: '/usr/bin',
      DEEPSEEK_API_KEY: 'secret',
      OPENAI_API_KEY: 'other',
      UNRELATED_SECRET: 'nope',
    },
    allowProviderEnv: true,
  })
  assert.equal(env.DEEPSEEK_API_KEY, 'secret')
  assert.equal(env.OPENAI_API_KEY, 'other')
  assert.equal(env.UNRELATED_SECRET, undefined)
})
