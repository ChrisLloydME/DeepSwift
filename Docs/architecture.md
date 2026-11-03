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
- `workspaceFiles` — list/read text files
- `account` — state, browser sign-in start/cancel, sign-out, profile
- `$events` — forwarded events and approval/user-question waterfalls

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

## Deliberate exclusions

- No WebView, React, Electron, or browser renderer.
- No second Agent engine, message database, or credential store.
- No `sudo`, privileged helper, global package installation, or background
  launch service.
- No automatic approval when an approval type is unknown.
