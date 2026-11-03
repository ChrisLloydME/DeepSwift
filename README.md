# DeepSwift

A native macOS client for **DeepSeek Harness (DSH)**. DeepSwift is written in
SwiftUI with AppKit where native behavior matters (the composer, panels, menus).
The DSH Agent runtime remains the official Node.js implementation; this
repository contains no second Agent engine and no WebView or React surface.

![status](https://img.shields.io/badge/status-developer%20preview-orange)

## What works

| Area | Status | Notes |
|---|---|---|
| Native window and navigation | Implemented | `NavigationSplitView`, native sidebar, toolbar, inspector, Settings, window restoration through standard scene behavior |
| Runtime isolation | Implemented | Explicit isolated `DSH_HOME`, allowlisted child environment, loopback port 0, parent-death watchdog |
| Runtime lifecycle | Implemented | Start, readiness, unexpected exit, reconnect with backoff, restart, graceful child shutdown |
| Workspaces | Implemented | List, create from `NSOpenPanel`, select; archive and pin state projected from Host |
| Sessions | Implemented | List, create, open, history paging, live follow, rename, archive/unarchive, running state |
| Conversation | Implemented | User/assistant messages, reasoning, streaming text, Markdown, fenced code, tables, tool cards, errors, interruption notices |
| Message composer | Implemented | AppKit `NSTextView`, IME-safe composition, Enter/Shift-Enter preference, image attachments, drag and drop |
| Tools | Implemented | Generic native tool card with per-tool icon/summary, collapsible arguments/output, errors and completion |
| Approvals | Implemented | Official Agent-scoped approval waterfall; Allow Once / Reject; fail-closed |
| User questions | Implemented | Native question sheet with options, multi-select, free text, plan-review detail |
| Model selection | Implemented | Official model catalog and session model selection |
| Account sign-in | Partial | Official browser OAuth start/cancel/sign-out wired; completion requires a real account and was not automated |
| Workspace files | Implemented | Host-enforced directory listing, text/code preview, copy, open externally |
| Search | Partial | Official `session/search` wired; no dedicated UI test yet |
| Background jobs | Partial | Official job list stream and human kill are wired; no dedicated UI test yet |
| Subagents | Partial | Listed and read-only conversation browsing; no subagent steering |
| Terminal | Not implemented | Deliberately absent rather than bypassing DSH with an uncontrolled shell |
| Diff / image / PDF preview | Not implemented | File preview reports a safe fallback for non-text files |
| Packaging / bundled Node | Not implemented | Development uses an isolated project-local runtime; see Phase 5 notes |
| Plugin/skill settings UI | Not implemented | Host plugin management remains available through DSH itself |
| UI tests | Placeholder | Unit and bridge tests are real; XCUITest coverage is not yet written |

Unsupported features are shown as unavailable rather than silently substituted.

## Build

Requirements:

- macOS 15 or later
- Xcode 27 (project format and SwiftUI APIs are current)
- Node.js **24.9.0 or later** for the development runtime

1. Open `DeepSwift.xcodeproj` in Xcode.
2. Run `Scripts/prepare-dev-runtime.sh` once. It installs the pinned official
   DSH package into `.local/runtime/bridge` with a project-local npm cache.
3. Build and run the `DeepSwift` scheme. For a dedicated development profile:

   ```sh
   DEEPSWIFT_DSH_HOME="$PWD/.local/profiles/dev" open -a DeepSwift
   ```

   The app defaults to `~/Library/Application Support/DeepSwift/DSHHome`.

DeepSwift never reads or writes `~/.dsh`, never updates a global DSH install,
and never changes global npm configuration. See
[Runtime Isolation](Docs/runtime-isolation.md).

### Sandboxing note

The Debug target currently has App Sandbox disabled. A development build
launches a user-installed Node runtime and reads project-local development
files; a sandboxed build would need the runtime and profile inside an app
container or an explicit bundled-runtime design. This is a development
configuration, not a claim that a sandboxed distribution is ready. Hardened
Runtime remains enabled, and no privileged helper is used.

## Runtime setup and credentials

The Host is the official `dsh --profile web` process, bound to loopback on an
OS-assigned port. The bridge authenticates through the official `/connect`
exchange and uses the official Remote HTTP API and event stream multiplexer.

Credentials belong to the isolated DSH profile. Sign in from
**Settings › Models › DeepSeek Account**. The Host opens the system browser and
stores the resulting grant itself; DeepSwift only observes the safe account
projection. Alternatively, for development only, enable
**Settings › Runtime › Pass provider API key environment variables** and export
`DEEPSEEK_API_KEY` in the launching environment.

No API key is written by this app, and no test sends a paid model request.

## Verification

```sh
Scripts/run-bridge-tests.sh
```

Runs the Node bridge protocol, isolation, and WebSocket tests. Swift unit tests
are run from Xcode (Test action) or the `RunSomeTests` Xcode tool; they cover
JSON transport, conversation projection, deduplication, streaming deltas,
pagination, runtime isolation, and prompt/approval request shapes.

## Documentation

- [Architecture](Docs/architecture.md)
- [Protocol compatibility](Docs/protocol-compatibility.md)
- [Runtime isolation](Docs/runtime-isolation.md)
- [Third-party notices](Docs/third-party-notices.md)
- [Feature coverage and limitations](#what-works)

## Repository layout

```text
Bridge/                  Dependency-free Node stdio bridge
  src/                   Host process, HTTP/WebSocket carrier, protocol
  tests/                 node:test suites
DeepSwift/               SwiftUI application target
  Models/                Transport and domain models, projection
  Services/              Bridge client and runtime configuration
  Views/                 Native views
DeepSwiftTests/          Swift Testing suites
Scripts/                 Isolated development runtime helpers
Docs/                    Architecture and compatibility documentation
.local/                  Disposable local runtime, profiles, logs (ignored)
```

## License

DeepSwift is a client for DeepSeek Harness. DeepSeek Harness is MIT licensed;
see [third-party notices](Docs/third-party-notices.md).
