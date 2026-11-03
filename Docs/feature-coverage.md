# Feature Coverage

Status reflects the current source and the verification actually performed. It
does not imply pixel parity with the official Electron client. Plugins and
automation tasks are excluded by product scope.

| Feature | Upstream support | DeepSwift status | Remaining work / limits | Verification |
|---|---|---|---|---|
| Native window/navigation | Yes | Complete | Single main window by design; Settings is a separate scene | Build; SwiftUI source |
| Session list/create/select | Yes | Complete | — | Swift unit tests; live Host tests |
| Session rename/archive/pin | Yes | Complete | — | Swift unit tests (projection); source |
| Session history paging | Yes | Complete | — | Swift unit tests |
| Live streaming assistant | Yes | Complete | — | Real OpenCode stream; live Host |
| Reasoning activity | Yes | Complete | Presentation is generic | Source; live Host |
| Tool cards/results/errors | Yes | Complete | Generic fallback card | Real write tool integration |
| Approvals | Yes | Complete | Allow Once/Reject; fail closed | Swift unit tests; source |
| User questions | Yes | Complete | Plan review supported | Source; preview data |
| Subagents | Yes | Partial | List/open/read-only; no steering or creation controls | Source |
| Slash commands | Yes | Complete | — | Swift unit tests |
| File references/attachments | Yes | Complete | Text + PNG/JPEG/GIF/WebP input | Swift unit tests |
| Permissions presets | Yes | Complete | Uses official `/permission` command; hides when absent | Live catalog probe; Swift unit test |
| Agent presets | Yes | Complete | Official `agentPresets/list/select`; hidden after the first turn locks composition | Live roster/selection probe; Swift unit test |
| Workspace register/switch/rename/remove | Yes | Complete | Reveal in Finder | Source |
| Workspace directory browsing | Yes | Complete | Host-scoped, no direct FileManager reads | Live Host binary read; source |
| Text/source preview | Yes | Complete | Line gutter + lightweight syntax highlighting; 5,000-line page | SwiftUI preview; source |
| Image preview | Yes | Complete | Native zoomable `NSImageView` in `NSScrollView` | Build; source |
| PDF preview | Yes | Complete | PDFKit continuous view | Build; source |
| Changed files summary | Yes | Complete | Latest live turn only; Host keeps history for its lifetime | Real turn: summary/diff |
| Diff viewing | Yes | Complete | Unified hunks, line colors, per-file navigation | Real turn: `+hello world` hunk |
| Terminal | Yes | Complete | SwiftTerm 1.2.5 + official terminal controller; sheet UI | Live PTY create, attach, input, output; preview |
| Background jobs | Yes | Complete | Native job roster sheet with progress, detail, and Stop; Inspector summary | Source |
| Message search | Yes | Partial | Official search endpoint and sheet; no automated integration test | Source |
| DeepSeek Account | Yes | Partial | OAuth start/cancel/sign-out wired; completion needs a real account | Source |
| DeepSeek API key | Yes | Complete | Official settings + credential services | Swift tests; live Host |
| Built-in providers/BYOK | Yes | Complete | Official directory/settings/discovery/select | Swift tests; live Host |
| Custom providers | Yes | Complete | OpenAI/Anthropic-compatible routes; manual models | Swift tests; source |
| OpenCode Go | Yes | Complete within pinned runtime | Live metadata; all current live IDs are in the installed catalog. Future live-only IDs are marked unavailable. Per-model routing preserved. | Live 28-model discovery; 30 installed; real inference |
| Model picker | Yes | Complete | Bounded searchable sheet, reasoning effort | Preview with 80 models |
| Settings | Yes | Complete for in-scope settings | Runtime, models, general, about/licenses; no update feed | Build; source |
| Native menus/shortcuts | Yes | Complete for implemented actions | No fake actions | Source |
| Runtime lifecycle/isolation | Yes | Complete | Parent watchdog, reconnect, restart | Node tests; packaged app launch |
| Bundled Node/DSH | Yes | Complete script path | Release needs Developer ID + notarization; Node is host-arch | Packaged app launched with bundled Node/DSH |
| Sparkle updates | Optional | Missing | No signed appcast/update key; intentionally not faked | — |
| Plugins UI | Yes | Excluded | Out of scope | — |
| Automation tasks | Yes | Excluded | Out of scope | — |
| Automated UI tests | — | Not default | `DeepSwiftUITests` is retained but not run for this work | — |

## Known upstream/runtime limitations

- Pinned `@deepseek-ai/dsh@0.2.1-rc.5` cannot add a new `opencode-go` model
  that is absent from its installed pi-ai catalog. Live-only models are shown
  as not routable; the app does not fabricate a route.
- The pinned `llm-pi-ai` configurable protocol surface exposes
  `openai-completions`, `openai-responses`, and `anthropic-messages`.
  `google-generative-ai` appears in OpenCode metadata and the installed
  `gemini-4-argon` entry, but custom Google routes are not offered.
- `workspace/changes` summaries are process-local to the live Host. A turn
  reopened after Host restart has no comparison, by upstream design.
- Terminal and Agent tools use the Host's execution environment. Development
  shells that restrict PTY creation will report a Host error; the packaged app
  was verified outside that restriction.
- Account OAuth completion, signing certificates, notarization, and update
  signing require external credentials and were not simulated.

## Verification levels

- **Xcode build:** Debug and Release app plus SwiftTerm framework; no code warnings
  (Xcode's AppIntents metadata note is tooling-only).
- **Swift unit tests:** focused suites listed in the final report.
- **Node tests:** bridge protocol, isolation, persistence, multipart binary read.
- **Isolated Host:** provider catalog, binary file read, terminal controller.
- **Real OpenCode Go:** model discovery, minimal inference, tool-backed write,
  changed-files summary, and unified diff.
- **SwiftUI Previews:** model picker, terminal surface, changed-files card, workspace source browser.
- **Packaged app:** Debug and Release bundles launched with bundled Node/DSH and
  a private profile; the Release Host reported ready and exited cleanly. The
  Debug app was also launched via LaunchServices with an isolated runtime, where
  the terminal controller created a PTY, attached a snapshot, and streamed
  input/output.
