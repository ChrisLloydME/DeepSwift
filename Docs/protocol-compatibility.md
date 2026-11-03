# DSH Protocol Compatibility

## Supported upstream

| Item | Value |
|---|---|
| Upstream | https://github.com/deepseek-ai/deepseek-harness |
| Runtime package | `@deepseek-ai/dsh` |
| Pinned version | `0.2.1-rc.5` |
| npm integrity | `sha512-WkyJZv4zl9sCAxSzRctGm58m0rilGqwR6pniBiLOz5CPDfHfDuAUicg0AAazXI7oj/Cph6/cjNTncA/rpLTXpw==` |
| Host profile | `web` |
| Bridge protocol | 1 |
| Node range | `>=24.9.0` |

The runtime is pinned in `Bridge/pinned-runtime.json` and installed by
`Scripts/prepare-dev-runtime.sh`. The application does not follow `latest`,
`alpha`, or a branch.

The upstream checkout used for protocol inspection was
`deepseek-ai/deepseek-harness@ce7073d51254c26cd63b22a60835b8f948deb447`
(2026-10-30), which publishes `0.2.2-alpha.2`. That prerelease was rejected for
this client: creating any session with the shipped `web` profile fails while
composing every agent preset with
`TypeError: Cannot read properties of undefined (reading 'parent')` in
`withinFiber` (`dsh-agent-preset-registry`). Disabling the preset registry
avoids the crash but removes the preset tool compositions. Version
`0.2.1-rc.5` creates the same sessions successfully and is the supported
baseline.

## Integration approach

DeepSwift uses the **official Node.js Host** and the **official wire
protocol**. It does not reimplement the Agent, tools, persistence, permissions,
or credentials.

The bridge speaks:

- the API-client connect exchange: `GET /connect?token=…&interactions=answer`;
- unary Remote calls: `POST /api/<namespace>/<method>` with the Connection
  `client-request` envelope;
- stream calls: logical `open`/`item`/`end`/`cancel` frames on
  `/api/remote.mux`;
- forwarded events and Agent-scoped waterfalls on the `$events` logical stream,
  answered through `POST /api/$events/result`.

### Why the TypeScript client modules are not imported

The official client modules (`@deepseek-ai/dsh-client-connection/client`,
`@deepseek-ai/dsh-api-remotes/client`, and the generated `/remote`
contributions) are deliberately designed for a Cordis client tree and a browser
carrier. The published packages document that the Gateway Client assembly is
React-independent, but it still requires the Cordis client runtime, generated
Typert contributions, and a browser/WebSocket generation source. Importing that
assembly into the bridge would add a large client runtime and a second state
model without changing the wire calls below.

The bridge instead uses the documented descriptors' wire field names and the
published protocol types as its source of truth. It is dependency-free. If
upstream changes field names or frame shapes, the compatibility surface is
confined to `Bridge/src/connection.mjs` and `Bridge/src/main.mjs`.

## Endpoints used

| Namespace / method | Wire args (shape) | Purpose |
|---|---|---|
| `workspace/follow` (stream) | `{}` | Workspace baseline, order, archive, pin, session membership |
| `workspace/create` | `{request:{path}}` | Register a workspace over a chosen directory |
| `workspace/archiveSession` | `{request:{sessionId,stopActivity}}` | Archive a session |
| `workspace/unarchiveSession` | `{request:{sessionId}}` | Restore an archived session |
| `session/list` | `{_request:{}}` | Session summaries and projection hints |
| `session/create` | `{request:{workspaceId?,cwd?,agentPreset?}}` | Create a session |
| `session/rename` | `{request:{sessionId,title}}` | Rename |
| `session/prompt` | `{request:{requestId,sessionId,mode,content,clientTimeZone?}}` | Submit text/image content |
| `session/cancel` | `{request:{sessionId}}` | Cancel the active turn |
| `session/page` | `{request:{address,throughSeq,beforeSeq?,maxMessages?,turnWindow?}}` | Read older history; `throughSeq` is required by 0.2.1-rc.5 |
| `session/follow` (stream) | `{request:{address,activate?,assistantStream?,maxMessages?,turnWindow?}}` | Opening snapshot + live durable events + assistant deltas |
| `session/control` (stream) | `{}` | Cross-session projection baseline/changes |
| `session/modelCatalog` | `{}` | Provider-grouped routable models |
| `settings/describe` | `{}` | Redacted settings values, schemas, revisions, and secret slots |
| `settings/mutate` | `{ns,ops,expectedRevision?}` | Path-addressed provider-settings writes |
| `credentials/describe` | `{refs}` | Redacted credential status and source; never values |
| `credentials/set` | `{ref,value}` | Write-only API-key storage in the isolated DSH profile |
| `credentials/unset` | `{ref}` | Remove a stored credential reference |
| `llm/listConfigurableProviders` | `{}` | Installed/custom provider directory and native-auth metadata |
| `llm/discoverModels` | `{settingsNs,request}` | Installed-catalog or endpoint model discovery |
| `session/selectModel` | `{request:{sessionId,provider,model,reasoningEffort?}}` | Session model selection |
| `session/search` | `{request:{query}}` | Durable message-content search |
| `commands/list` | `{agentId}` | Effective slash-command descriptors |
| `commands/execute` | `{agentId,line,submittedAttachments}` | Execute a recognized slash command; null means fall back to prompt |
| `job/list` (stream) | `{request:{sessionId}}` | Complete visible job roster |
| `job/kill` | `{request:{sessionId,jobId}}` | Human cancellation of a job |
| `workspaceFiles/list` | `{workspaceFileScopeId,path}` | Workspace directory entries |
| `workspaceFiles/read` | `{workspaceFileScopeId,path,range:{offset,limit}}` | Text file page |
| `account/getState` | `{}` | Safe account projection |
| `account/startSignIn` | `{client,callbackOrigin,loginSource}` | Browser OAuth attempt |
| `account/cancelSignIn` | `{attemptId}` | Cancel a local attempt |
| `account/signOut` | `{client}` | Remove the local grant |
| `account/getProfile` | `{client}` | Display-safe profile |
| `$events` (stream) | `{args:{}}` | Forwarded emits and waterfalls |
| `$events/result` | `{args:{clientId,eventId,outcome}}` | Waterfall reply |

### OpenCode Go compatibility

OpenCode Go is supplied by the pinned pi-ai catalog. Its models use different
wire protocols and endpoints (`openai-completions`, `openai-responses`, and
`anthropic-messages`) and the provider appends `x-opencode-session` from the
session id that the DSH Agent already passes to every model stream.

DeepSwift adds one narrowly scoped bridge method for live metadata:

| Bridge method | Args | Purpose |
|---|---|---|
| `opencode.discoverModels` | `{}` | Fetch and decode `https://opencode.ai/inference/go/v1/models` |

The method sends an identifying `DeepSwift/1.0 (macOS)` User-Agent and
`x-opencode-client: deepswift`, and sends no credential because the metadata
endpoint is public. It returns protocol, endpoint, context/output limits,
modalities, and reasoning metadata for inspection. It is read-only: routing
still comes from the installed DSH catalog, so a live response never replaces
configured models.

The pinned `llm-pi-ai` adapter does not consult this endpoint for an installed
route; its `llm/discoverModels` returns the installed catalog. DeepSwift uses
that catalog for installed-model counts and uses the bridge method only for the
live OpenCode metadata view. Because a route-level `api` or `baseURL` would
override every per-model protocol/endpoint, the Models UI never writes those
overrides for the built-in OpenCode Go route and offers an explicit
"Restore Installed Catalog" action for stale profiles.

`workspaceFileScope` is a Typert lookup. Its wire field is
`workspaceFileScopeId`, carrying the selected session id. The Host resolves the
session's workspace root; the client never supplies an authoritative root.

## Interaction waterfalls

Approval and question requests arrive as `type: "waterfall"` frames on
`$events`:

```json
{
  "type": "waterfall",
  "event": "approval/request",
  "eventId": "…",
  "agentId": "…",
  "request": { "toolName": "bash", "callId": "…", "reason": "…" }
}
```

The bridge forwards a UI-facing event and waits. The reply is:

```json
{
  "clientId": "…",
  "eventId": "…",
  "outcome": { "kind": "result", "value": "allowed-once" }
}
```

Approval outcomes are the closed set `allowed-once`, `rejected`, `cancelled`,
`unavailable`. Unknown waterfall events are delegated with
`{"kind":"next"}`; they are never auto-approved. A pending request that loses
its connection generation is invalidated and the UI removes it.

User-question results use `{answers:[{id,selected,custom?}]}` or
`{cancelled:true}`.

## Session event projection assumptions

DeepSwift consumes `session/follow` snapshots and events. The projection is
tolerant of unknown event types.

Currently rendered:

- `user/message` where `source.kind == "user"`;
- `assistant/message` (`message.content`: text, reasoning, tool-call);
- `assistant/attempt` (message and nested stream failure);
- `tool/call`, `tool/result`;
- `session/title`, `permission/preset`, `command/done`, `turn/end`;
- process-local `assistant-stream` frames (`start`, `chunk`, `end`) with
  `text-delta`, `reasoning-delta`, `tool-call-delta`, `block-end`.

Deliberately ignored or summarized:

- runtime context and time snapshots (`user/message` with non-user sources);
- request headers/context, inbox splicing, step and turn boundaries;
- unknown tool event names (the tool card remains generic);
- unknown session event types.

This avoids inventing semantics for DSH presentation surfaces that are not part
of the stable session vocabulary.

## Known unsupported upstream surfaces

| Surface | Status | Fallback |
|---|---|---|
| Terminal controller streams | Unsupported | No shell is started; terminal stays unavailable |
| Binary file transfer / image preview | Unsupported in this bridge | Text preview or a safe "preview unavailable" message |
| Diff rendering | Unsupported | Tool output shows the exact textual result |
| Session fork / queue edit / pin / workspace delete | API known, UI absent | Not exposed rather than approximated |
| Plugin/skill management | API known, UI absent | Use official DSH tooling |
| Subagent steering | Read-only browsing | No prompt is sent to a subagent session |
| `session/load` transcript replay | Not used | `session/follow` snapshot is authoritative |
| Additional workspace directories | Unsupported by upstream ACP/Desktop flows | Single session workspace |

## Upgrade checklist

When moving the pin:

1. Run `Scripts/prepare-dev-runtime.sh` with the new version and integrity.
2. Start a session with the `web` profile and verify preset composition.
3. Verify the endpoint/args table against generated `/remote` descriptors.
4. Re-run `Scripts/run-bridge-tests.sh` and the Swift unit tests.
5. Manually exercise: session create, prompt, streaming, cancel, approval,
   question, history page, search, job list, file list/read, account state.
6. Update this document and `Docs/third-party-notices.md`.
