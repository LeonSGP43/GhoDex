# Android Remote Control Blueprint

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
   - Exposes WebSocket for duplex events/commands and HTTP for pairing/bootstrap endpoints if needed.
   - Runs on separate queues from the current local Unix-socket harness.

4. `ControlHarnessAuth`
   - New authentication and session layer.
   - Handles pairing, token issuance, token rotation, session expiration, and command authorization.

5. `ControlHarnessRateLimiter`
   - New request budgeting and abuse protection layer.
   - Enforces per-client and global ceilings for reads, commands, subscriptions, and reconnection churn.

6. `RemoteApprovalPolicy`
   - New policy adapter that maps remote mutation intents to `AITerminalManagedState`.
   - Blocks or defers risky commands when state is `manual`, `managed_waiting_approval`, or otherwise unapproved.

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

### Desktop files to add

- `macos/Sources/Features/Control Harness/ControlHarnessGateway.swift`
- `macos/Sources/Features/Control Harness/ControlHarnessGatewayProtocol.swift`
- `macos/Sources/Features/Control Harness/ControlHarnessGatewayClientSession.swift`
- `macos/Sources/Features/Control Harness/ControlHarnessAuth.swift`
- `macos/Sources/Features/Control Harness/ControlHarnessRateLimiter.swift`
- `macos/Sources/Features/Control Harness/ControlHarnessReadSampler.swift`
- `macos/Sources/Features/Control Harness/ControlHarnessSampleStore.swift`
- `macos/Sources/Features/Control Harness/ControlHarnessRemotePolicy.swift`

### Desktop files to modify

- `macos/Sources/Features/Control Harness/ControlHarnessCore.swift`
- `macos/Sources/Features/Control Harness/ControlHarnessService.swift`
- `macos/Sources/Features/Control Harness/ControlHarnessSupport.swift`
- `macos/Sources/App/macOS/AppDelegate.swift`
- `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift`
- `macos/Sources/Features/AI Terminal Manager/AITerminalManagerModels.swift`
- `macos/Sources/Features/AI Terminal Manager/AITerminalManagerStore.swift`

### Tests to add

- `macos/Tests/ControlHarness/ControlHarnessGatewayTests.swift`
- `macos/Tests/ControlHarness/ControlHarnessReadSamplerTests.swift`
- `macos/Tests/ControlHarness/ControlHarnessRateLimiterTests.swift`
- `macos/Tests/ControlHarness/ControlHarnessAuthTests.swift`
- `macos/Tests/ControlHarness/ControlHarnessBackpressureTests.swift`

## Milestones

### Milestone 0: Contract Freeze

Goal:

- Freeze the remote protocol contract before building Android UI.

Must prove:

- command names and payload shapes are stable enough for a client
- delta/snapshot lineage rules are documented
- overflow and resync semantics are documented

### Milestone 1: Low-Impact Desktop Foundation

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

### Milestone 2: Gateway Isolation

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

### Milestone 3: Auth and Policy

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

### Milestone 4: Android MVP

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

### Milestone 5: Shannon Integration

Goal:

- Introduce richer orchestration only after control plane is stable.

Scope:

- bridge task and approval semantics into Shannon
- surface remote approval events and managed task summaries
- preserve compatibility with Android client contract

Must prove:

- Shannon integration does not become a new hot path for terminal rendering
- gateway contract remains backward compatible or versioned

## Acceptance Metrics

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
