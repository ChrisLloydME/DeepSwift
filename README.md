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
| Workspaces | Implemented | List, create from `NSOpenPanel`, rename, remove registration, select; archive and pin state projected from Host |
| Sessions | Implemented | List, create, open, history paging, live follow, rename, archive/unarchive, running state, subagent browsing |
| Conversation | Implemented | User/assistant messages, reasoning, streaming text, Markdown, fenced code, tables, tool cards, errors, interruption notices |
| Message composer | Implemented | AppKit `NSTextView`, IME-safe composition, Enter/Shift-Enter preference, image attachments, drag and drop, official slash-command suggestions |
| Tools | Implemented | Generic native tool card with per-tool icon/summary, collapsible arguments/output, errors and completion |
| Approvals | Implemented | Official Agent-scoped approval waterfall; Allow Once / Reject; fail-closed |
| User questions | Implemented | Native question sheet with options, multi-select, free text, plan-review detail |
| Model selection | Implemented | Official provider-grouped catalog, reasoning efforts, session model selection, explicit unavailable-model state, and a bounded searchable picker sheet |
| Agent and permission presets | Implemented | Official `agentPresets` roster/selection before a session's first turn; official `/permission` command for permission presets |
| OpenCode Go | Implemented and live-verified | Installed mixed-protocol catalog preserved; live metadata inspection; accurate client headers; stale route overrides reset; minimal real inference and tool turn verified |
| File references | Implemented | Local Markdown links open the native workspace preview; external links use the system browser |
| Model providers / BYOK | Implemented | Official provider directory and settings APIs; DeepSeek API key, installed pi-ai providers, custom OpenAI- and Anthropic-compatible routes; official model discovery; write-only DSH credentials |
| Account sign-in | Partial | Official browser OAuth start/cancel/sign-out wired; completion requires a real account and was not automated |
| Workspace files | Implemented | Host-enforced directory listing, syntax-highlighted source preview, zoomable images, PDFKit previews, copy, open externally |
| Changed files / diff | Implemented | Live-turn summary card and native unified diff viewer with per-file navigation |
| Terminal | Implemented | Official DSH terminal controller through a vendored SwiftTerm framework; attach/input/resize/exit and retained sessions |
| Search | Partial | Official `session/search` wired; no automated integration verification |
| Background jobs | Implemented | Official job roster stream, progress/detail, and native Stop action |
| Subagents | Partial | Listed and read-only conversation browsing; no steering/creation controls |
| Packaging / bundled Node | Implemented scripts | Release script embeds self-contained Node, bridge, and pinned DSH; signing/notarization needs external credentials |
| Plugin/skill settings UI | Not implemented | Host plugin management remains available through DSH itself |
| UI tests | Retained, not default | Legacy end-to-end tests; work verification uses unit, Node, Host, and preview checks |

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

### Standalone packaging

```sh
Scripts/prepare-node-runtime.sh
Scripts/build-release.sh
```

`prepare-node-runtime.sh` downloads an official self-contained Node.js build
with checksum verification into `.local/node`. `build-release.sh` creates a
Release app, copies Node, the bridge, and the pinned DSH graph into
`Contents/Resources`, and emits a zipped app. Set
`DEEPSWIFT_CODESIGN_IDENTITY` to a Developer ID identity for distribution, then
run `Scripts/notarize.sh` with Apple notary credentials. See
[Runtime Isolation](Docs/runtime-isolation.md#packaged-runtime).

### Sandboxing note

The Debug target keeps App Sandbox disabled because its development workflow
uses a project-local Node runtime and profile. The packaged runtime layout is
implemented and launch-verified outside App Sandbox; an App Store sandboxed
distribution would require a container-specific runtime/profile migration and
is not claimed. Hardened Runtime remains enabled, and no privileged helper is
used.

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

No API key is written by this app. Routine unit and Node tests use mocks or
fixtures. A narrowly scoped, manually run OpenCode Go integration check used a
minimal real inference request; it is not part of the automated test suite.

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
- [Feature coverage and limitations](Docs/feature-coverage.md)

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
Scripts/                 Isolated runtime, packaging, signing, and test helpers
SwiftTerm/                Vendored SwiftTerm 1.2.5 framework (MIT)
Docs/                    Architecture and compatibility documentation
.local/                  Disposable local runtime, profiles, logs (ignored)
```

## License

DeepSwift is a client for DeepSeek Harness. DeepSeek Harness is MIT licensed;
see [third-party notices](Docs/third-party-notices.md).
