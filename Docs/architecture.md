# Architecture

DeepSwift is a native presentation and state-projection layer over the official
DeepSeek Harness Host. The Host and its Agent runtime are authoritative for
sessions, messages, tools, approvals, workspaces, files, and account state.

```text
┌──────────────────────────────────────────────────────────────┐
│ DeepSwift.app (SwiftUI + AppKit)                             │
│                                                              │
│  Views ──► AppModel (@MainActor, Observation)                │
│              │                                               │
│              ├── ConversationProjection (value type)         │
│              ├── Workspace/Session/Job projections           │
│              └── DSHBridgeService (protocol, mockable)       │
│                        │                                     │
│                  BridgeClient (actor)                        │
└────────────────────────┼─────────────────────────────────────┘
                         │ newline-delimited JSON over stdio
┌────────────────────────▼─────────────────────────────────────┐
│ Bridge/src/main.mjs (Node.js, no runtime dependencies)       │
│                                                              │
│  HostRuntime ── official `dsh --profile web` child           │
│  HostConnection ── /connect cookie + HTTP Remote calls       │
│  WebSocketClient ── /api/remote.mux logical streams          │
└────────────────────────┬─────────────────────────────────────┘
                         │ authenticated loopback HTTP + WebSocket
┌────────────────────────▼─────────────────────────────────────┐
│ Official DSH Host (isolated DSH_HOME)                        │
│  Agent/Session runtime · tools · workspace · credentials     │
│  HTTP API gateway · Remote streams · web server              │
└──────────────────────────────────────────────────────────────┘
```

## Swift boundaries

### `DSHBridgeService`

A `nonisolated` protocol with four operations and one notification stream:

- `start(configuration:)`
- `request(_:params:timeout:)`
- `stop()`
- `notifications: AsyncStream<BridgeNotification>`

`BridgeClient` is the production actor. Tests use `MockBridgeService` and never
start Node. This keeps views and application state independent of transport.

### `AppModel`

`@MainActor @Observable` state used by SwiftUI. It:

- owns the selected workspace/session and visible sheets,
- opens the workspace and session-control streams,
- opens exactly one conversation follow stream for the selected session,
- folds bridge events into `ConversationProjection`,
- forwards commands through stable bridge methods,
- maintains a queue of pending approvals and questions,
- exposes runtime, account, model, file, job, and search state.

Views do not parse DSH RPC frames and do not spawn processes.

### `ConversationProjection`

A `Sendable` value type that folds durable `SessionWireEvent` values and
process-local assistant deltas into `ChatItem` values. It provides:

- sequence-number deduplication,
- stable message/tool identities,
- user/assistant/reasoning/tool/notice/error items,
- context-message filtering (runtime/time snapshots never masquerade as user
  input),
- tool result attachment by `callId`,
- streaming text/reasoning accumulation,
- older-page prepending without duplicating the live window.

The view observes one value; no second message database exists.

## Bridge boundaries

The bridge is intentionally thin and dependency-free:

- `host-process.mjs` spawns and reaps the Host, builds the isolated environment,
  captures the ready URL, and retains a bounded stderr tail.
- `connection.mjs` performs the official connect-cookie exchange, unary Remote
  calls, and the logical stream mux.
- `websocket.mjs` is a minimal RFC 6455 text client (masking, ping/pong,
  fragmentation, close); binary frames are refused.
- `protocol.mjs` validates request framing and reports `BridgeError` values.
- `main.mjs` routes methods, forwards events, handles approval/question
  waterfalls, and reconnects the mux.

Bridge methods are versioned by `bridge.hello.protocolVersion` (currently 1):

| Direction | Frame |
|---|---|
| Swift → bridge | `{ "id": "...", "method": "...", "params": { ... } }` |
| bridge → Swift | `{ "id": "...", "result": ... }` |
| bridge → Swift | `{ "id": "...", "error": { code, message, details } }` |
| bridge → Swift | `{ "event": "...", "data": ... }` |

The bridge never logs to stdout. Every diagnostic goes to
`<DSH_HOME>/logs/bridge.log` and stderr.

## Host integration

`HostConnection` uses the documented API-client flow:

1. `GET /connect?token=...&interactions=answer` → 302 with an API cookie.
2. Unary calls: `POST /api/<namespace>/<method>` with a Connection envelope.
3. Streams: logical `open`/`item`/`end`/`cancel` frames on
   `/api/remote.mux`.
4. Forwarded interactions: `$events` stream frames, answered through
   `POST /api/$events/result`.

The app uses these official namespaces:

- `workspace` — follow, create, archive/unarchive, pin state
- `session` — list, create, rename, prompt, cancel, events, follow, model
  catalog/selection, search
- `session/control` — all-session projection baseline/changes
- `job` — per-session list stream and human kill
- `workspaceFiles` — directory listing, paged text, and native bytes
- `terminal` — list/create/attach/close for Host-owned PTYs
- `permissionPresets` — selectable presets; switching uses the official
  `/permission` command
- `account` — state, browser sign-in start/cancel, sign-out, profile
- `/api/changes.summary` and `/api/changes.diff` — authenticated changed-file
  summaries and comparisons
- `$events` — forwarded events and approval/user-question waterfalls

## Provider settings and BYOK

Provider configuration is a projection of the official Host, not a second
configuration database:

- `llm/listConfigurableProviders` supplies the installed provider directory,
  including native-auth hints and custom routes declared by settings.
- `settings/describe` supplies redacted namespace values, user overrides,
  secret-slot state, and revisions.
- `settings/mutate` applies path-addressed operations with the observed
  revision, so unrelated providers and unknown fields survive edits.
- `credentials/describe` supplies only `configured`, `source`, and `writable`.
  `credentials/set` is the only value-bearing direction; the value is never
  retained by `AppModel` or returned by the Host.
- `llm/discoverModels` returns candidate model metadata. Discovery is optional;
  the editor also accepts manual identifiers, and a partial endpoint response
  never removes existing model entries.
- Configured installed providers are counted from `llm/discoverModels` without
  a credential (the installed catalog does not resolve a key), so a row reflects
  its catalog even when the key is missing. Custom routes are excluded from
  that refresh because they would perform network I/O.
- OpenCode Go is treated as a managed mixed-protocol provider. Its route-level
  `api`/`baseURL` and model list are never written by the normal editor; an
  explicit reset restores the installed catalog. Live metadata is read-only
  through the bridge's `opencode.discoverModels` compatibility endpoint.
- `session/modelCatalog` remains the sole source for the conversation model
  picker. Adding or changing a provider triggers a fresh catalog read, so the
  picker and settings page agree.

The native Models page separates DeepSeek Account, the direct DeepSeek API-key
route, installed pi-ai providers, and custom pi-ai routes. Provider IDs are
stable; custom IDs are immutable after creation because they are the settings
key, request route, and credential-reference stem. API keys are entered with
`SecureField` and can be revealed only for the current unsaved draft.

Only `llm-pi-ai` routes can be hand-declared; the direct `llm-deepseek` route
is a composition fact and is edited rather than created. Account sign-in and
API-key authentication remain distinct routes and catalog groups.

## Files, changes, and terminal

- File listings and text reads remain Host-scoped. `workspaceFiles/readBytes`
  returns the official multipart binary envelope; the bridge decodes it into
  base64 so Swift can render PNG/JPEG/GIF/WebP images and PDFs without direct
  `FileManager` access.
- Text preview is a native scroll view with a line gutter and lightweight
  syntax highlighting. It is a viewer, not an editor.
- `workspace/changes` events carry only a turn number. The Host's authenticated
  `/api/changes.summary` and `/api/changes.diff` routes provide the files and
  unified hunks. The app folds the latest live announcement into a card and a
  bounded review sheet. Summaries do not survive a Host restart.
- Terminal processes are owned by the Host terminal controller. `SwiftTerm`
  is a separate dynamic framework linked into the app and embedded in
  `Contents/Frameworks`; it only parses VT sequences and translates keyboard
  input. Terminal stream IDs are unique per attachment, and a snapshot resets
  the emulator before incremental output is applied.
- Permission presets use `/permission <preset>`; the app does not write the
  sandbox or approval knobs directly.

## Concurrency and lifecycle

- Swift UI state is `@MainActor`; transport is an actor.
- SDK calls are async; streams are consumed with `for await`.
- Bridge calls have bounded timeouts; a timeout fails only that call.
- The bridge reconnects the mux with capped exponential backoff and reopens
  logical streams. Swift receives `stream.reset` before replacement data.
- A conversation reopening receives a fresh snapshot; sequence deduplication
  prevents double-rendering if a frame overlaps the old window.
- A parent-death watchdog, stdin EOF, stdout EPIPE, SIGTERM, and SIGINT all
  converge on a single idempotent shutdown that stops only the owned child.
- The app distinguishes window close from termination. Window close leaves the
  runtime available; application termination stops the bridge, which stops the
  Host.

## Native UI decisions

- `NavigationSplitView` for the main shell, `List` for navigation, native
  toolbar, search field, menus, alerts, sheets, and `Settings` scene.
- The trailing inspector is attached to the detail column, not to the split
  view itself. The window-level toolbar owns the single inspector toggle; the
  conversation header and inspector content never declare their own toolbar
  controls. Inspector visibility lives only in `AppModel.showInspector`.
- The window toolbar background is hidden so the inspector's system glass
  material continues behind the native toolbar. This is a window-level
  appearance choice; there is no custom background, blur overlay, or fixed
  toolbar offset in the inspector.
- Inspector metadata uses a grouped `Form` with `Section` and
  `LabeledContent`, native text selection, and system semantic colors.
- `NSTextView` in an `NSScrollView` for the composer. Marked text is never
  replaced by SwiftUI updates, preserving CJK input methods.
- Native `NSOpenPanel` for workspaces and image attachments.
- Semantic colors and materials for Light/Dark Mode.
- Tool cards use a generic renderer with tool-specific display names/icons;
  unknown tools remain renderable.
- Markdown uses `AttributedString` for inline formatting, with explicit native
  blocks for fenced code and pipe tables.
- SwiftTerm's upstream `Color` type is renamed `TerminalColor` only inside the
  vendored framework to avoid colliding with SwiftUI `Color`; the terminal
  surface itself is an AppKit `NSView` bridged through `NSViewRepresentable`.
- The app uses a single `Window` scene so one process owns one runtime and one
  Host. Settings is a separate native scene.

## Deliberate exclusions

- No WebView, React, Electron, or browser renderer.
- No second Agent engine, message database, or credential store.
- No `sudo`, privileged helper, global package installation, or background
  launch service.
- No automatic approval when an approval type is unknown.
