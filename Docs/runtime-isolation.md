# Runtime Isolation

DeepSwift development and testing must never disturb an existing DSH
installation or the user's real sessions and credentials.

## Home directory policy

The bridge requires `DEEPSWIFT_DSH_HOME` to be an absolute, explicit directory.
`HostRuntime` refuses:

- `~/.dsh`
- `~/.config/dsh`
- `~/Library/Application Support/dsh`
- any path that resolves to one of the above through symlinks
- relative, empty, or non-directory paths

It creates the directory with mode `0700` when absent. There is no fallback to a
default DSH home. A missing profile is an error, not a reason to read the user's
profile.

Resolution order in the app:

1. `DEEPSWIFT_DSH_HOME` environment variable (development and tests)
2. `dshHomeOverride` in app preferences
3. `~/Library/Application Support/DeepSwift/DSHHome`

Tests use dedicated directories under `.local/profiles/`.

## Child environment

The Host does not inherit the ambient process environment wholesale. The
allowlist is:

```text
PATH, HOME, TMPDIR, TMP, TEMP, LANG, LC_ALL, LC_CTYPE, TERM, TZ,
USER, LOGNAME, SHELL
```

DeepSwift then sets:

```text
DSH_HOME=<isolated home>
DSH_AGENTS_HOME=<isolated home>/agents
NO_COLOR=1
npm_config_cache=<isolated home>/cache/npm
npm_config_update_notifier=false
```

Every ambient `DSH_*` variable is removed, including `DSH_AGENTS_HOME`; the Host's shared agent instructions and skills therefore stay inside the isolated profile rather than reading the user's `~/.agents`. Provider API keys are passed only
when the user explicitly enables **Settings › Runtime › Pass provider API key
environment variables**. In that case only variables matching
`DEEPSEEK_*`, `OPENAI_*`, or `ANTHROPIC_*` are copied. They are never written to
disk by DeepSwift.

## Provider credentials

DeepSwift does not implement a Swift credential database and does not copy
provider keys into Keychain. API keys entered in Models settings are written
through the official DSH credentials service into the **isolated profile's**
DSH-managed credential store (`.credentials.yaml` under the isolated home).
The Host returns only redacted status (`configured`, `source`, `writable`) and
never returns the stored value. Removing a provider or credential is done
through the official settings and credentials APIs as well.

Custom providers may name a credential reference directly. When that reference
is supplied only by the launching environment, the Runtime setting controls
whether the three allowed provider prefixes are passed; stored credentials
always take precedence over the environment inside DSH.

## Runtime installation

`Scripts/prepare-dev-runtime.sh`:

- installs `@deepseek-ai/dsh@0.2.1-rc.5` into `.local/runtime/bridge`;
- sets `npm_config_cache` and `npm_config_userconfig` to `.local/cache`;
- sets `npm_config_logs_dir` under `.local/cache`;
- uses `--no-audit --no-fund`;
- approves install scripts only for the native/runtime dependencies required by
  the pinned DSH package;
- never uses `-g`, `sudo`, or a global prefix.

Nothing in this repository edits `~/.npmrc`, `~/.npm`, a global DSH install, or
shell startup files.

## Network and IPC

- Host bind address is always `127.0.0.1`.
- The port is `0`, so the OS chooses a free port. No fixed port is claimed.
- Authentication uses the official short-lived launch token and API cookie.
- The bridge holds a loopback WebSocket to the Host it owns.
- No listening socket is opened by DeepSwift itself.
- No Unix socket is needed because the bridge uses stdio for its own client
  boundary.
- The application never connects to a Host it did not spawn.

## Process ownership

- The bridge spawns exactly one Host child with `detached: false`.
- Stop escalates only that pid: `SIGTERM`, bounded grace, then `SIGKILL`.
- No process groups, names, or unrelated pids are signalled.
- The Host receives stdin EOF when the app exits.
- A parent-death watchdog checks `process.ppid` every two seconds and shuts down
  if the app disappeared.
- An stdout/stderr EPIPE is treated as parent loss and converges on the same
  shutdown path.
- Shutdown is idempotent and reaps the Host before the bridge exits.
- Unexpected Host termination is reported to Swift; the bridge does not
  automatically spawn a replacement. The user or app can explicitly restart.
- Mux disconnection with a live Host reconnects with capped exponential
  backoff and reopens logical streams.

Window close does not terminate the app. Application termination stops the
runtime. There is no privileged helper and no launch daemon.

## Test data

- Test profiles: `.local/profiles/<test-name>`
- Test workspaces: `.local/workspaces/<test-name>`
- Logs and sockets: `.local/logs`, `.local/sockets`
- npm cache: `.local/cache/npm`
- Upstream checkout: `.local/upstream/deepseek-harness`

`.local/` is ignored by Git. Automated tests do not use real provider
credentials and do not run Agent tools in a real user workspace. The bridge
tests validate protocol and isolation without starting DSH; the Swift
projection tests replay fixtures only.

## Manual verification

```sh
# Confirm the bridge refuses the real home
DEEPSWIFT_DSH_HOME="$HOME/.dsh" node Bridge/src/main.mjs
# expected: bridge.failed with a configuration error

# Use an isolated development profile
DEEPSWIFT_DSH_HOME="$PWD/.local/profiles/dev" open -a DeepSwift
```

Inspect a running Host's port and token only from the isolated profile's log:

```sh
cat "$HOME/Library/Application Support/DeepSwift/DSHHome/logs/host.log"
```

Do not reuse that URL against a different profile.
