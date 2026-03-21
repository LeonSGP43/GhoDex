# Android Remote Control Blueprint

## Status Legend

- `completed`: implemented in this worktree and covered by current code/tests
- `in_progress`: partially implemented or implemented but still missing acceptance evidence
- `pending`: intentionally not started in this worktree
- `drift`: the original file/module plan no longer matches the actual implementation shape

## Current Status Snapshot

Status date: `2026-03-21`

- Overall desktop-side status: `in_progress`
- Milestone 0 status: `completed`
- Milestone 1 status: `completed`
- Milestone 2 status: `completed`
- Milestone 3 status: `completed`
- Milestone 4 status: `in_progress`
- Milestone 5 status: `pending`
- Acceptance metrics status: `in_progress`

Current reality:

- The desktop-side gateway, sampled-read path, auth/token lifecycle, policy gate, rate limiting, TCP transport, WebSocket transport, backpressure, replay, and local performance snapshots are implemented.
- A minimal Android client contract foundation now exists in the repo as pure Java request/resume models, but there is still no full Android app, transport binding, or UI shell in this worktree.
- Shannon integration is not implemented in this repo/worktree.
- Performance instrumentation exists, but the blueprint's representative macOS acceptance measurements have not yet been recorded.

## Goal

Build an Android app that can observe and control GhoDex tabs and terminal sessions with low latency while keeping desktop rendering, input responsiveness, and normal local workflows effectively unaffected.

## Target Outcome

- Android observes terminal state through structured events and sampled text frames, not remote-desktop streaming.
- Android writes through structured terminal commands, not UI click simulation.
- Desktop-side remote support is isolated behind a gateway layer so slow or abusive mobile clients do not stall GhoDex's local control path.
- Approval and managed-state policy remain the source of truth for risky remote mutations.

## Current Repo Leverage Points

- `ControlHarnessCore` already exposes a structured control protocol:
  - `handshake`
  - `snapshot`
  - `new-tab`
  - `close-tab`
  - `send-text`
  - `run-command`
  - `read-terminal`
  - `close-terminal`
  - `events.subscribe`
- `ControlHarnessEventHub` already provides:
  - monotonic sequence numbers
  - JSONL persistence
  - replay after reconnect
- `ControlHarnessTerminalReadStore` already provides:
  - frame IDs
  - delta generation
  - changed-row output
  - paged windows
  - read-after-write readiness checks
- `SurfaceView_AppKit` already maintains visible and screen text caches.
- `AITerminalManagedState` already defines the control-policy states needed for remote approval gating.

## Hard Decisions

### 1. Do not use remote-desktop as the primary architecture

Remote-desktop streaming is rejected for the main path because it is worse on bandwidth, battery, responsiveness, operability, and maintainability than the structured control protocol already present in this repo.

### 2. Keep GhoDex local-first

The desktop app remains the primary UX. Remote support must behave like an attached control plane, not like a mode that re-architects the terminal runtime around the phone.

### 3. Gateway isolation is mandatory

No Android client may talk directly to the current Unix-socket service over the network. A dedicated gateway must sit in front of it and absorb network, authentication, backpressure, and rate-limit concerns.

### 4. Push sync is mandatory

Android must not poll `read-terminal` at high frequency. The steady-state model is:

- subscribe to event stream
- receive sampled frame/update notifications
- fetch delta or compact snapshot only when needed
- fall back to snapshot after a buffer gap or protocol mismatch

## Target Architecture

### Desktop Side

1. `ControlHarnessCore`
   - Remains the authoritative control-plane core for terminal operations.
   - Continues to own generation checks, idempotency, and terminal mutations.

2. `ControlHarnessReadSampler`
   - New sampling layer for terminal text.
   - Produces sampled visible/screen frames on a scheduler instead of relying on client-triggered fresh reads.
   - Maintains per-terminal sampled snapshots and freshness metadata.

3. `ControlHarnessGateway`
   - New network-facing gateway.
   - Exposes WebSocket for duplex events/commands and a raw TCP JSON transport today.
   - HTTP pairing/bootstrap endpoints remain optional and are not implemented in this worktree.
   - Runs on separate queues from the current local Unix-socket harness.

4. `ControlHarnessAuth`
   - New authentication and session layer.
   - Handles pairing, token issuance, token rotation, session expiration, and command authorization.

5. `ControlHarnessRateLimiter`
   - New request budgeting and abuse protection layer.
   - Enforces per-client and global ceilings for reads, commands, subscriptions, and reconnection churn.
   - Current implementation note: this exists as types and logic embedded in `ControlHarnessGateway.swift`, not as a standalone file.

6. `RemoteApprovalPolicy`
   - New policy adapter that maps remote mutation intents to `AITerminalManagedState`.
   - Blocks or defers risky commands when state is `manual`, `managed_waiting_approval`, or otherwise unapproved.
   - Current implementation note: this is currently wired through `AppDelegate.controlHarnessGatewayAccessDecision(...)`, not a standalone module.

### Android Side

1. `GatewayClient`
   - WebSocket client with resume support.
   - Tracks auth state, reconnects with `since_sequence`, and restores terminal subscriptions.

2. `SessionIndexStore`
   - Local state for tabs, terminals, working directories, and managed states.
   - Seeded by `snapshot`, then advanced by event replay/live stream.

3. `TerminalBufferStore`
   - Local line-buffer engine keyed by terminal ID and frame ID.
   - Applies `delta` frames when possible and falls back to snapshot on gaps or invalid lineage.

4. `CommandComposer`
   - Sends only structured mutations:
   - `send-text`
   - `run-command`
   - `new-tab`
   - `close-terminal`

5. `ApprovalUI`
   - Shows blocked or approval-required operations before execution.

## Data Flow

### Read Path

1. Desktop sampler produces sampled frames for visible and screen scopes.
2. Gateway emits lightweight update events referencing terminal ID, scope, frame ID, parent frame ID, freshness, and sampled timestamp.
3. Android receives the event and decides:
   - apply inline delta if present
   - request delta by `since_frame_id`
   - request compact snapshot if gap detected
4. Android updates its local terminal buffer and renders immediately.

### Write Path

1. Android sends a structured mutation to gateway.
2. Gateway authenticates, rate-limits, and checks remote authorization policy.
3. Core executes the mutation through existing terminal control paths.
4. Event stream emits sequence-backed mutation event.
5. Android waits for matching write acknowledgment and then consumes subsequent sampled frame events.

## Required Refactor Direction

### A. Decouple network handling from the main actor

Current issue:

- `ControlHarnessService` accepts clients on concurrent queues but forwards request handling through `Task { @MainActor ... }`.
- Subscription writes are performed directly against the client socket.

Required direction:

- keep local Unix-socket service intact for same-host tooling
- add a separate gateway with its own accept loop, worker queues, bounded outbound buffers, and backpressure rules
- minimize the work that reaches the main actor to terminal-control operations and sampler refreshes only

### B. Move remote reads onto sampled cache semantics

Current issue:

- `read-terminal` can force `refresh`, which performs a fresh terminal text read on the main actor
- this is acceptable for local tooling and read-after-write verification, but not as the steady-state mobile sync path

Required direction:

- sampler owns regular capture cadence
- Android reads sampled frames by default
- forced fresh reads become rare, budgeted, and preferably debug-only for remote clients

### C. Add explicit backpressure and overflow semantics

Current issue:

- current subscription path can block on client socket writes
- event fanout is too trusting of subscriber throughput

Required direction:

- per-client ring buffer
- explicit overflow marker or `gap: true`
- client must resync by snapshot after overflow
- no unbounded buffering

## Sampling Policy

### Terminal Priority Classes

1. `managed_active` and currently selected remote terminal
   - visible scope sample every `100ms` to `150ms`
   - screen scope sample every `300ms` to `500ms`

2. `observed`
   - visible scope sample every `400ms` to `750ms`
   - screen scope sample every `1s` or on notable events only

3. `manual` or inactive background terminals
   - no aggressive periodic sampling
   - refresh only on coarse interval such as `2s` to `5s`, focus change, or meaningful terminal activity signal

### Adaptive Rules

- Reduce cadence when client app is backgrounded.
- Reduce cadence when the terminal content is stable.
- Increase cadence only for the actively viewed terminal on Android.
- Never scale all terminals up to active cadence simultaneously.

## Gateway Rules

### Authentication

- Pairing starts locally on desktop with a short-lived pairing code or QR.
- Gateway issues a scoped token after successful pairing.
- Tokens are revocable and expire.
- Mutation scope can be narrower than observation scope.

### Authorization

- Observation allowed for paired clients.
- Structured writes allowed only when policy permits.
- High-risk operations may require desktop-side approval.
- `manual` terminals must not be silently remote-controlled.

### Rate Limits

- Cap concurrent gateway sessions per paired identity.
- Cap per-client:
  - commands per minute
  - snapshot requests per minute
  - resync attempts per minute
- Add a global safety ceiling to preserve desktop responsiveness under abusive traffic.

### Backpressure

- Each subscribed client gets a bounded outbound queue.
- Recommended initial limits:
  - `256` events max
  - or `1 MiB` buffered payload, whichever is hit first
- On overflow:
  - drop oldest buffered updates
  - emit overflow/gap marker
  - require client snapshot resync

## File and Module Plan

Current status: `drift`

Reason:

- The desktop implementation grew slightly differently than this original file map.
- Some planned modules landed as integrated types inside `ControlHarnessGateway.swift` or `AppDelegate.swift`.
- Test coverage landed in the existing `ControlHarnessTests.swift` file instead of being split into dedicated test files.

### Desktop files to add

- `macos/Sources/Features/Control Harness/ControlHarnessGateway.swift` - `completed`
- `macos/Sources/Features/Control Harness/ControlHarnessGatewayProtocol.swift` - `completed`
- `macos/Sources/Features/Control Harness/ControlHarnessGatewayClientSession.swift` - `completed`
- `macos/Sources/Features/Control Harness/ControlHarnessAuth.swift` - `completed`
- `macos/Sources/Features/Control Harness/ControlHarnessRateLimiter.swift` - `drift`
- `macos/Sources/Features/Control Harness/ControlHarnessReadSampler.swift` - `completed`
- `macos/Sources/Features/Control Harness/ControlHarnessSampleStore.swift` - `completed`
- `macos/Sources/Features/Control Harness/ControlHarnessRemotePolicy.swift` - `drift`

### Desktop files to modify

- `macos/Sources/Features/Control Harness/ControlHarnessCore.swift` - `completed`
- `macos/Sources/Features/Control Harness/ControlHarnessService.swift` - `pending`
- `macos/Sources/Features/Control Harness/ControlHarnessSupport.swift` - `completed`
- `macos/Sources/App/macOS/AppDelegate.swift` - `completed`
- `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift` - `pending`
- `macos/Sources/Features/AI Terminal Manager/AITerminalManagerModels.swift` - `pending`
- `macos/Sources/Features/AI Terminal Manager/AITerminalManagerStore.swift` - `pending`

### Tests to add

- `macos/Tests/ControlHarness/ControlHarnessGatewayTests.swift` - `drift`
- `macos/Tests/ControlHarness/ControlHarnessReadSamplerTests.swift` - `drift`
- `macos/Tests/ControlHarness/ControlHarnessRateLimiterTests.swift` - `drift`
- `macos/Tests/ControlHarness/ControlHarnessAuthTests.swift` - `drift`
- `macos/Tests/ControlHarness/ControlHarnessBackpressureTests.swift` - `drift`

Actual test status:

- `macos/Tests/ControlHarness/ControlHarnessTests.swift` currently contains the gateway, sampler, auth, rate-limit, backpressure, TCP, and WebSocket coverage for this worktree.

## Milestones

### Milestone 0: Contract Freeze

Status: `completed`

Goal:

- Freeze the remote protocol contract before building Android UI.

Must prove:

- command names and payload shapes are stable enough for a client
- delta/snapshot lineage rules are documented
- overflow and resync semantics are documented

Current evidence:

- The blueprint documents the protocol shape and replay/gap semantics.
- The gateway exposes stable `gateway.*`, `snapshot`, `read-terminal`, and `events.subscribe` command handling on both TCP and WebSocket transports.

### Milestone 1: Low-Impact Desktop Foundation

Status: `completed`

Goal:

- Make desktop-side remote support safe before opening network access.

Work:

- add sampler and sample store
- make remote reads default to sampled cache
- define activity classes and sampling scheduler
- add gateway queues and outbound buffering design

Must prove:

- no high-frequency mobile polling path exists in the steady state
- inactive/manual terminals stay on low cadence
- sampled reads can drive terminal view updates without forcing fresh main-actor reads

Current evidence:

- `ControlHarnessReadSampler` and `ControlHarnessSampleStore` are implemented.
- `read-terminal` now prefers sampled data, checks freshness, and invalidates samples after writes.
- Sampling cadence already separates `managed_active`, `observed`, and background/manual terminals.

### Milestone 2: Gateway Isolation

Status: `completed`

Goal:

- Expose network access without coupling slow clients to local control paths.

Work:

- add WebSocket gateway
- add per-client session lifecycle
- add backpressure, overflow markers, and reconnect replay support

Must prove:

- slow client cannot block local Unix-socket control harness
- one slow client does not degrade other remote clients
- disconnect and reconnect with `since_sequence` works cleanly

Current evidence:

- The gateway now runs as a separate TCP/WebSocket listener with per-client buffering and session caps.
- Overflow emits explicit resync markers.
- Replay/live event subscription is covered by current TCP and WebSocket tests.

### Milestone 3: Auth and Policy

Status: `completed`

Goal:

- Prevent unsafe or abusive remote control.

Work:

- pairing and token model
- session revocation
- mutation authorization policy
- rate limits

Must prove:

- unauthenticated client cannot observe or mutate
- rate limits fail closed
- risky writes are blocked or approval-gated

Current evidence:

- Pairing, token issue, token rotate, token revoke, expiration, and disk persistence are implemented.
- AppDelegate now enforces managed-state-aware remote mutation policy.
- Global, command, snapshot, and resync request limits fail closed before core dispatch.

### Milestone 4: Android MVP

Status: `in_progress`

Goal:

- Deliver a useful mobile control surface after desktop safety is proven.

Scope:

- connection/pairing
- terminal index
- active terminal text view
- run command / send text
- reconnect and replay
- approval-required UX

Must prove:

- active terminal view stays current without polling
- snapshot fallback recovers from overflow/gap
- remote writes are acknowledged and reflected in subsequent sampled updates

Current gap:

- A compileable Android client contract foundation and a minimal `android/app` transport UI shell now exist in this worktree, and one local emulator install/run path has been verified. The remaining gaps are WebSocket parity, richer approval-oriented mobile UX, and broader device-level validation.

### Milestone 5: Shannon Integration

Status: `pending`

Goal:

- Introduce richer orchestration only after control plane is stable.

Scope:

- bridge task and approval semantics into Shannon
- surface remote approval events and managed task summaries
- preserve compatibility with Android client contract

Must prove:

- Shannon integration does not become a new hot path for terminal rendering
- gateway contract remains backward compatible or versioned

Current gap:

- No Shannon-side bridge or compatibility/versioning layer exists in this worktree yet.

## Acceptance Metrics

Status: `in_progress`

The system cannot be called complete until these are met on a representative macOS build:

- With one Android client observing one active terminal:
  - no perceptible local typing lag
  - added app CPU in idle observation remains low and bounded
- With one Android client observing five terminals where only one is active:
  - background terminals remain on reduced cadence
  - no visible local render hitching during active terminal use
- Under a slow or intentionally blocked mobile connection:
  - local desktop interaction remains responsive
  - gateway sheds or resyncs the slow client instead of backlogging the desktop path
- Remote reconnect after temporary disconnect:
  - replay by `since_sequence` succeeds
  - snapshot fallback repairs missed frame history
- Unauthorized or rate-limited clients:
  - fail cleanly
  - do not trigger unbounded logging, queue growth, or main-thread churn

Recommended initial measurable targets:

- steady-state observation adds less than `5%` process CPU on idle desktop for one active observed terminal
- extra main-thread work from remote support stays below `2ms p95` per frame during ordinary local use
- active-terminal update latency to Android stays under `150ms p95` on same-LAN Wi-Fi
- inactive-terminal update latency stays under `1s`
- overflow recovery to a valid snapshot completes within `2s` on same-LAN Wi-Fi

Current evidence and gap:

- `gateway.metrics` now exposes rolling sampler/gateway timing snapshots for local inspection.
- The representative macOS benchmark and latency runs required by this section have not yet been recorded in this worktree.
- Therefore the desktop slice is feature-complete through Milestone 3, but not acceptance-complete.

## No-Compromise Rules

- No remote-desktop primary path.
- No steady-state high-frequency polling from Android.
- No unbounded outbound buffering.
- No direct network exposure of the current local Unix-socket service.
- No remote mutation path that bypasses approval and managed-state policy.
- No optimization that spreads terminal-core edits deep into Zig unless profiling proves it is necessary.

## Decision Trail

- The repo already contains a strong structured control-plane foundation, so the correct move is to promote and isolate it, not replace it.
- The largest current desktop-risk points are main-actor request handling, socket-coupled subscription writes, and client-triggered fresh reads.
- Therefore the implementation order must be:
  1. sampler and sampled-cache semantics
  2. gateway isolation and backpressure
  3. auth and rate limiting
  4. Android client
  5. Shannon enrichment

This order optimizes for performance safety first and user-facing breadth second.
