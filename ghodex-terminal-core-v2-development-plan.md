# GhoDex Terminal Core V2 Development Plan

## Objective
Build a high-performance terminal synchronization and extraction architecture that:

1. Delivers SSH-like real-time control from mobile.
2. Replaces current harness read-screen primary path with V2 stream/snapshot/semantic paths.
3. Enforces strict memory lifecycle and bounded buffers.
4. Keeps desktop rendering behavior stable.

## Task 1 - V2 Protocol Skeleton in Control Harness

### SPEC
- Add V2 commands:
  - `terminal.stream.open`
  - `terminal.stream.ack`
  - `terminal.snapshot.v2`
  - `terminal.semantic.v2`
- Keep compatibility with existing `read-terminal` and `events.subscribe`.
- Add request fields required for V2 control:
  - `stream_id`
  - `ack_bytes`
  - `last_ack_sequence`

### Acceptance Strategy
- Handshake command list includes all V2 commands.
- `terminal.stream.open` returns subscription envelope and session metadata.
- `terminal.stream.ack` validates payload and returns deterministic ack state.
- `terminal.snapshot.v2` and `terminal.semantic.v2` return valid payloads for an existing terminal.
- Existing commands still work.

### Tests
- Unit tests for each new command success path.
- Unit tests for invalid argument paths (`terminal_id` missing/invalid, `ack_bytes <= 0`).
- Unit tests ensure unsupported command behavior is unchanged.

## Task 2 - Memory-Managed Stream Session Store

### SPEC
- Introduce per-terminal stream state store with bounded memory behavior:
  - track active streams
  - track unacked bytes
  - fixed high/low watermark configuration
- Explicit cleanup paths:
  - terminal close
  - stream close
  - ack update
- No unbounded accumulation in store structures.

### Acceptance Strategy
- Opening stream allocates exactly one stream state entry.
- Closing terminal clears all terminal stream states.
- Ack never causes negative counters.
- Store enforces a maximum stream count and evicts stale entries safely.

### Tests
- Unit test for open -> ack -> close lifecycle.
- Unit test for terminal close cleanup.
- Unit test for bounded stream count eviction behavior.

## Task 3 - Harness Read Path Replacement Entry

### SPEC
- Add V2 read entrypoints in `ControlHarnessCore`:
  - snapshot data path (`terminal.snapshot.v2`)
  - semantic projection path (`terminal.semantic.v2`)
- Use existing terminal readable surface for first-stage bootstrap, but route through V2 commands.
- Keep `read-terminal` as fallback path only.

### Acceptance Strategy
- V2 snapshot/semantic commands are callable from gateway and return stable payload shape.
- Existing mobile/harness integrations can migrate to V2 without breaking old calls.

### Tests
- Snapshot V2 content round-trip test with ANSI payload.
- Semantic V2 logical lines extraction test.

## Task 4 - Gateway and Authorization Wiring

### SPEC
- Update gateway auth scope and category routing for V2 commands:
  - observe-scope commands: `terminal.stream.open`, `terminal.stream.ack`, `terminal.snapshot.v2`, `terminal.semantic.v2`
- Update app-level subscription dispatch so subscription commands are routed by command kind, not hard-coded to `events.subscribe`.

### Acceptance Strategy
- Auth denies/permits V2 commands with expected scope behavior.
- Subscription flow remains stable for both `events.subscribe` and `terminal.stream.open`.

### Tests
- Gateway unit tests for scope checks and category mapping.
- Subscription flow test with `terminal.stream.open`.

## Task 5 - Follow-up Implementation Phases (After Skeleton)

### SPEC
- Phase 2: PTY output chunk push path and real backpressure.
- Phase 3: migrate mobile default path to V2 stream + snapshot seed + ack.
- Phase 4: switch AI/harness default reads to semantic service.

### Acceptance Strategy
- Each phase gated by:
  - functional correctness
  - bounded memory behavior
  - no desktop rendering regression
- New path becomes default only after passing phase acceptance tests.

### Tests
- Throughput and soak tests.
- reconnect/gap/snapshot-resync tests.
- long-running memory stability checks.

## Task 6 - Phase 2 Slice A: Stream Chunk Pump + Ack Backpressure

### SPEC
- `terminal.stream.open` must return a live subscription session (not metadata-only) that can emit terminal chunk records.
- Stream chunk records must include stream identity + terminal identity + delta metadata:
  - `stream_kind=terminal_chunk`
  - `stream_id`
  - `terminal_id`
  - `generation`
  - `frame_id` / `parent_frame_id`
  - `delta_kind`
  - `content`
- Backpressure must be enforced in stream store:
  - chunk emission increases `unacked_bytes`
  - when `unacked_bytes >= high_watermark_bytes`, flow pauses
  - `terminal.stream.ack` reduces `unacked_bytes`
  - flow resumes only when `unacked_bytes <= low_watermark_bytes`
- Closing a terminal or subscription must release stream-state entries to avoid accumulation.

### Acceptance Strategy
- Opening a stream produces at least one seed/replay chunk for the terminal.
- Live chunk pumping emits updates when terminal content changes.
- With tiny watermark config, stream pauses after one/few chunks and resumes only after ack.
- Subscription close and `close-terminal` both reclaim stream entries.

### Tests
- Unit test: stream open -> receive terminal chunk payload shape.
- Unit test: backpressure pause/resume with high/low watermark + ack.
- Unit test: stream state cleaned when terminal closes or stream session closes.

## Task 7 - Phase 3 Slice A: Mobile Gateway V2 Snapshot/Semantic API Wiring

### SPEC
- Add mobile gateway APIs for V2 read entrypoints:
  - `terminal.snapshot.v2`
  - `terminal.semantic.v2`
- Keep existing `read-terminal` API untouched for fallback compatibility.
- Parse V2 responses into typed mobile results with deterministic field mapping.

### Acceptance Strategy
- Mobile can call V2 snapshot command and receive parsed frame/content metadata.
- Mobile can call V2 semantic command and receive logical-lines extraction payload.
- Legacy `read-terminal` calls remain behavior-compatible.

### Tests
- Unit test: `terminal.snapshot.v2` request payload and response parse mapping.
- Unit test: `terminal.semantic.v2` request payload and response parse mapping.
- Unit test: missing `terminal_id` still fails fast before network send.

## Task 8 - Phase 3 Slice B: Mobile Terminal Read Path Switch to V2 Snapshot (With Safe Fallback)

### SPEC
- In workspace terminal refresh flow, use `terminal.snapshot.v2` as the default snapshot read path.
- Keep legacy `read-terminal` delta path for incremental row-patch updates in this slice.
- Preserve fallback safety:
  - delta lineage mismatch -> snapshot fallback
  - when `read_after_write_id` is required, keep legacy snapshot path so readiness semantics are unchanged.
- Keep UI state shape compatible (`TerminalReadResult`) by mapping V2 snapshot payload into existing local read model.

### Acceptance Strategy
- Manual/initial terminal reads use V2 snapshot command without breaking current renderer update flow.
- Delta refresh still works through legacy delta API and can fallback to snapshot safely.
- Write-settle logic keeps read-after-write readiness semantics (legacy snapshot path when needed).

### Tests
- Unit test: map V2 snapshot payload to `TerminalReadResult` compatibility shape.
- Unit test: unchanged frame id mapping reports `hasChanges=false`, changed frame id reports `hasChanges=true`.
- Existing transport helper tests still pass.

## Task 9 - Phase 3 Slice C: Mobile Gateway Terminal Stream API Wiring

### SPEC
- Add mobile gateway APIs for stream commands:
  - `terminal.stream.open` subscription handshake
  - `terminal.stream.ack` flow-control request
- Parse stream-open ack metadata and terminal chunk records (`stream_kind=terminal_chunk`).
- Keep event subscription API unchanged.

### Acceptance Strategy
- Mobile can open terminal stream and receive ack envelope + terminal chunk callbacks.
- Mobile can send ack for stream bytes and parse deterministic ack state.
- Stream socket failure paths surface meaningful errors.

### Tests
- Unit test: stream open sends `terminal.stream.open` with terminal identity and parses open result.
- Unit test: stream chunk callback receives decoded chunk record payload.
- Unit test: `terminal.stream.ack` request payload and response parse mapping.

## Task 10 - Phase 3 Slice D: Workspace Stream-First Live Path (Open/Chunk/Ack + Fallback)

### SPEC
- Workspace realtime refresh path must use `terminal.stream.open` as the default live transport for the selected terminal.
- Stream chunk handling must:
  - consume `terminal_chunk` records,
  - apply snapshot/reset chunks directly,
  - apply row delta chunks through deterministic row patch mapping when available.
- Stream flow control must be active in mobile:
  - accumulate received bytes,
  - send `terminal.stream.ack` with bounded batching,
  - recover from transient ack/session-limit errors with bounded retry.
- Compatibility and safety:
  - keep `events.subscribe` for structure-level updates (tab/terminal metadata changes),
  - if stream channel is unavailable or chunk lineage cannot be applied safely, fallback to snapshot refresh path.

### Acceptance Strategy
- With live updates enabled, selected terminal live refresh no longer depends on `events.subscribe`-triggered read polling as the primary path.
- Stream chunks update terminal content/render rows directly for reset and row delta updates.
- Ack requests are emitted deterministically as chunks are consumed and do not grow unbounded pending bytes.
- When stream drops/fails, workspace recovers via existing snapshot/delta fallback path without breaking session usability.

### Tests
- Unit test: map `terminal_chunk` reset payload to compatibility `TerminalReadResult` shape.
- Unit test: map `terminal_chunk` row delta payload with `changed_rows` to merge-safe compatibility shape.
- Unit test: stream ack byte accounting helper batches and drains pending bytes deterministically.
- Existing gateway stream API tests remain green.
