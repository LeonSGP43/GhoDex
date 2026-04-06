# GhoDex Agent Runtime V1 Spec Plan

## 0. Status

- Worktree: `feat/agent-runtime-v1`
- Document role: this file is the execution spec, not a brainstorming note.
- Goal: turn GhoDex into a host-owned Agent Runtime that can be driven by one or more Codex tabs without making any tab the source of truth.
- Current implementation state in this worktree:
  - runtime models and persistence are implemented
  - runtime-first projection is implemented
  - Control Harness runtime command surface is implemented
  - managed Codex bootstrap environment contract and socket attach lifecycle are implemented
  - browser / vision task kinds and canonical executor capabilities are implemented on the shared runtime contract
  - approval, stale recovery, and release/expiry cleanup are implemented
  - schedule / loop layer is implemented above runtime tasks
  - legacy external heartbeat inbox mutation is blocked by default
  - JSONL runtime event log is implemented
- Latest clean verification evidence:
  - prerequisite: `zig build -Demit-macos-app=false`
  - `xcodebuild test -project macos/GhoDex.xcodeproj -scheme GhoDex -destination 'platform=macOS' -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' -only-testing:GhosttyTests/AITerminalManagerTests -only-testing:GhosttyTests/ControlHarnessTests -only-testing:GhosttyTests/ControlHarnessHostEnvironmentTests -only-testing:GhosttyTests/AgentRuntimeContractsTests`
  - result: `** TEST SUCCEEDED **`
  - xcresult: `/Users/leongong/Library/Developer/Xcode/DerivedData/GhoDex-cppxzhjxylyexzayrocpyqoxmalc/Logs/Test/Test-GhoDex-2026.04.06_16-41-34-+0800.xcresult`
- This document now serves both as the locked spec and the completion/acceptance ledger for the implemented V1 scope.

## 1. Final Architecture Decision

### 1.1 System Shape

- `GhoDex host process` owns runtime truth.
- `Codex tab` is a runtime client, not a runtime owner.
- `Control Harness` is the transport and policy boundary.
- `Terminal / Browser / Vision` are execution planes under runtime dispatch.

### 1.2 Explicit Rejection

The following design is rejected and must not be implemented:

- a single Codex tab as the authoritative controller
- tab memory as the only task state
- direct tab-to-AppKit private control for runtime lifecycle
- separate shadow state machines for runtime and UI management state

### 1.3 Required Runtime Principle

All durable agent semantics must be host-owned:

- sessions
- leases
- task queue
- ownership
- approval waits
- stale recovery
- audit trail

## 2. V1 Scope

### 2.1 In Scope

- terminal-focused runtime lifecycle
- multiple Codex tabs as runtime clients
- runtime-backed managed state projection
- runtime command family in existing Control Harness
- managed Codex bootstrap environment
- stale session recovery
- deterministic task ownership
- runtime event logging

### 2.2 Explicitly Out Of Scope For Release Gate

- browser-native scheduling orchestration as a release blocker
- visual click executor as a release blocker
- distributed remote runtime cluster
- autonomous prompt-side state ownership
- agent marketplace or multi-user policy system

Browser and vision seams must remain integrable, but V1 release acceptance is terminal-first.

## 3. Hard Invariants

These are mandatory and non-negotiable.

### 3.1 Single Source Of Truth

- `AgentRuntimeSession` and `AgentRuntimeTask` are the only durable truth for runtime lifecycle.
- `AITerminalTaskRecord`, `taskBindings`, and `managedState` may exist temporarily only as compatibility projection or legacy fallback.
- No new feature may be built on top of legacy task truth.

### 3.2 Runtime Ownership

- runtime is global to the GhoDex host instance
- every Codex tab attaches as a client
- no tab can become runtime owner

### 3.3 Command Boundary

- Codex must interact with runtime only through Control Harness commands
- no direct Swift/AppKit runtime mutation from Codex integration glue
- no Codex tab may mutate runtime or queue state by writing heartbeat inbox files directly

### 3.4 Recovery Safety

- missing heartbeat must always lead to deterministic expiry handling
- active claimed work must always be requeued or paused according to policy
- ambiguity must fail closed

### 3.5 Projection Rule

- UI-facing `managedState`, badges, sampler activity, and session task summary are projections
- projection must prefer runtime truth
- legacy values may only be used as fallback where runtime has no matching data

## 4. Runtime Spec

### 4.1 Session Model

`AgentRuntimeSession` must continue to represent:

- `id`
- `clientKind`
- `tabID`
- `terminalID`
- `hostWorkspaceID`
- `state`
- `capabilities`
- `createdAt`
- `updatedAt`
- `lastHeartbeatAt`
- `leaseDurationSeconds`
- `leaseExpiresAt`
- `currentTaskID`
- `lastError`

### 4.2 Task Model

`AgentRuntimeTask` must continue to represent:

- `id`
- `kind`
- `state`
- `priority`
- `sessionID`
- `capabilityRequirements`
- `payload`
- `createdAt`
- `scheduledAt`
- `claimedAt`
- `finishedAt`
- `retryCount`
- `maxRetryCount`
- `errorSummary`

### 4.3 Task Ordering

Claim order must remain:

1. higher `priority`
2. earlier `scheduledAt`
3. earlier `createdAt`
4. UUID tie-break

This ordering is already in code and must not change without an explicit spec update.

### 4.4 Compatibility Projection Rules

Compatibility mapping from runtime to legacy UI/task states:

- `booting` / `active` session -> `managed_active`
- `waiting_approval` session -> `managed_waiting_approval`
- `paused` session -> `managed_paused`
- `expired` / `failed` session -> `managed_failed`
- `released` session -> fall back to compatibility registration state or `manual`

Task compatibility mapping:

- `claimed` / `running` -> legacy `active`
- `waiting_approval` -> legacy `waiting_approval`
- `paused` -> legacy `paused`
- `completed` -> legacy `completed`
- `failed` / `cancelled` -> legacy `failed`
- `queued` must not appear as the active projected current task for a claimed session

## 5. Multi-Tab Client Spec

### 5.1 Client Model

Multiple Codex tabs must be supported concurrently.

Each tab is a runtime client with:

- session identity
- capabilities
- lease heartbeat
- optional claimed task

### 5.2 Roles

V1 capability model must support at least:

- `runtime.observe`
- `runtime.task.claim`
- `runtime.task.manage`
- `runtime.executor.terminal`
- `runtime.executor.browser`
- `runtime.executor.vision`
- `runtime.admin`

Initial implementation may still map these onto coarse `observe` / `mutate` transport scopes, but the runtime-level capability names must be fixed in the contract now.

### 5.3 Ownership Rules

- only the owning session may update its claimed task
- a session with an unfinished current task may not claim another
- stale session ownership must be cleared by host recovery only

## 6. Control Harness Runtime Contract

V1 must extend the existing socket and command surface. No second runtime socket is allowed for V1 unless there is a blocking technical reason.

### 6.1 Required Commands

- `agent.runtime.snapshot`
- `agent.runtime.session.register`
- `agent.runtime.session.heartbeat`
- `agent.runtime.session.release`
- `agent.runtime.task.enqueue`
- `agent.runtime.task.claim_next`
- `agent.runtime.task.update`
- `agent.runtime.task.approve`
- `agent.runtime.task.cancel`
- `agent.runtime.schedule.enqueue`
- `agent.runtime.schedule.update`
- `agent.runtime.schedule.cancel`

### 6.2 Request Requirements

Every runtime mutation command must support:

- `request_id`
- `protocol_version`
- idempotency behavior consistent with existing harness mutation rules
- deterministic error codes

### 6.3 Error Requirements

V1 runtime commands must expose deterministic failures for:

- runtime disabled
- session not found
- session expired
- task not found
- task owner mismatch
- invalid task transition
- schedule not found
- invalid schedule transition
- invalid argument

### 6.4 Handshake Requirement

`handshake` must advertise runtime commands once implemented.

Acceptance rule:

- if a runtime command ships, it must appear in handshake command discovery

## 7. Managed Codex Bootstrap Spec

Managed Codex launch must provide host-discoverable bootstrap data through environment variables, and the launched bootstrap script must use that contract to self-register, heartbeat, and release over the existing Control Harness socket.

### 7.1 Required Bootstrap Keys

- `GHODEX_CONTROL_SOCKET`
- `GHODEX_AGENT_RUNTIME_SOCKET`
- `GHODEX_AGENT_RUNTIME_SESSION_KIND`
- `GHODEX_AGENT_RUNTIME_CLIENT_ID`
- `GHODEX_AGENT_RUNTIME_WORKSPACE_ID`
- `GHODEX_AGENT_RUNTIME_CAPABILITIES`
- `GHODEX_AGENT_RUNTIME_DEFAULT_HEARTBEAT_SECONDS`

### 7.2 Rules

- Codex integration must not require manual socket discovery
- Codex integration must not require manual prompt copy-paste of runtime identifiers
- managed bootstrap is host responsibility, not prompt responsibility
- `GHODEX_AGENT_RUNTIME_SOCKET` must resolve to the same socket path as `GHODEX_CONTROL_SOCKET` in V1
- `GHODEX_AGENT_RUNTIME_SESSION_KIND` must be host-issued and fixed to `codex_tab` for V1 managed launches
- `GHODEX_AGENT_RUNTIME_CLIENT_ID` must be host-issued per launch and non-empty
- `GHODEX_AGENT_RUNTIME_CAPABILITIES` must be deterministic host-issued CSV, not prompt text
- `GHODEX_AGENT_RUNTIME_WORKSPACE_ID` is optional and may only be present when the host knows workspace identity
- managed bootstrap must register its runtime session before entering the long-running `codex1m exec` path
- managed bootstrap must emit runtime heartbeats on the same socket while the managed Codex process remains alive
- managed bootstrap must release the runtime session on shell exit and must not leave a best-effort orphan behind when the wrapper exits cleanly

## 8. UI / Compatibility Spec

### 8.1 Required Projection Targets

The following reads must become runtime-first:

- AI Terminal Manager session list
- session `managedState`
- current task badge
- AppDelegate remote control policy
- Control Harness sampling activity

### 8.2 Allowed Transitional State

During migration, legacy task data may remain writable internally, but:

- runtime-first projection must drive visible state
- no new UI or access rule may read legacy task truth directly if runtime data exists

## 9. Delivery Order

## P0. Spec Lock

### Deliverables

- this plan file updated and accepted as the working spec

### Acceptance

- architecture boundary is unambiguous
- release scope is unambiguous
- invariants are explicit
- every phase below has concrete acceptance and tests

### Tests

- none

## P1. Runtime-First Projection Integration

Status: implemented and verified in this worktree.

### Deliverables

- add runtime projection helpers in AI Terminal Manager store
- make session summaries runtime-first
- make AppDelegate managed-state checks runtime-first
- keep legacy fallback only where runtime data is absent

### Acceptance

- if runtime session/task exists for a terminal, session summary reflects runtime state first
- remote-control gating uses projected runtime managed state
- sampler activity uses projected runtime managed state
- no visible session row prefers legacy task state over runtime task state when runtime data exists

### Tests

- `AITerminalManagerTests`
- add projection tests for runtime session state
- add projection tests for runtime task compatibility state
- add fallback test for legacy-only session state

## P2. Runtime Command Surface

Status: implemented and verified in this worktree.

### Deliverables

- add runtime commands to Control Harness
- add request decoding fields needed by runtime commands
- add runtime error mapping
- advertise commands in handshake

### Acceptance

- register / heartbeat / release / enqueue / claim / update / cancel work through Control Harness
- approve and schedule commands work through Control Harness
- handshake exposes the commands
- runtime commands obey query vs mutation behavior
- `agent.runtime.snapshot` is a strict read-only projection and must not persist expiry/recovery side effects
- wrong-owner and invalid-transition failures are deterministic

### Tests

- `ControlHarnessTests`
- handshake command discovery tests
- runtime command happy-path tests
- invalid argument tests
- runtime disabled matrix tests
- read-only snapshot projection tests
- heartbeat tick disabled-runtime regression test
- stale / wrong-owner / invalid-transition tests

## P3. Managed Codex Bootstrap

Status: implemented and verified in this worktree.

### Deliverables

- inject runtime bootstrap environment for managed Codex launches
- make the managed Codex wrapper self-register over the existing Control Harness socket
- make the managed Codex wrapper maintain heartbeats while `codex1m exec` is active
- make the managed Codex wrapper release the runtime session on exit
- document bootstrap keys in code comments and plan

### Acceptance

- managed Codex tab can discover runtime socket and self-register without manual edits
- managed Codex bootstrap attaches to runtime on the existing harness socket before handing off to `codex1m exec`
- managed Codex bootstrap sends periodic `agent.runtime.session.heartbeat` requests while the session is alive
- managed Codex bootstrap sends `agent.runtime.session.release` on orderly shell exit
- bootstrap metadata is stable enough for skill wrapper integration
- non-managed terminals must not retain stale `GHODEX_AGENT_RUNTIME_*` keys
- bootstrap values are host-issued and deterministic for the launch role

### Tests

- environment injection tests where practical
- smoke verification via launch configuration unit coverage
- `ControlHarnessHostEnvironmentTests`

## P4. Approval And Recovery Hardening

Status: implemented and verified in this worktree.

### Deliverables

- waiting-approval flow fully runtime-owned
- stale recovery visibly updates session/task projection
- release / expiry behavior closes ownership cleanly

### Acceptance

- approval wait blocks remote mutation correctly
- missing heartbeat triggers policy-defined recovery
- no orphan claimed task remains after expiry

### Tests

- `AITerminalManagerTests`
- lease expiry recovery tests
- approval state projection tests

## P5. Schedule / Loop Layer

Status: implemented and verified in this worktree.

### Deliverables

- add `Schedule` model above `Task`
- generate task instances from schedule rules
- support future run and loop semantics without overloading base task truth

### Acceptance

- scheduled work produces normal runtime tasks
- loop behavior is recoverable after restart
- runtime task model is not overloaded with recurrence-only fields

### Tests

- schedule generation tests
- future task due-time tests
- loop resume / recovery tests

## 10. Global Acceptance Gates

The feature is not considered complete unless all of the following are true:

- there is only one durable runtime truth
- runtime commands exist on the existing harness path
- Codex runtime mutation does not depend on heartbeat inbox file writes
- session summaries are runtime-first
- AppDelegate access control is runtime-first
- stale recovery is deterministic
- multiple Codex tabs are architecturally supported by contract, even if UI polish is minimal
- tests cover both compatibility and runtime-specific behavior

## 11. External Review Notes Locked Into This Spec

The following review outcomes are now part of the execution contract:

- heartbeat queue is dispatch plumbing, not runtime truth
- Control Harness remains the only supported runtime mutation boundary for Codex tabs
- bootstrap environment is a formal host-issued contract, not informal prompt glue
- restart handling must never leave running work in ambiguous state

## 12. Definition Of Done

Done means:

- code implements the phase deliverables
- acceptance rules in that phase pass
- named tests exist and pass
- no new shadow task truth was introduced
- plan file remains aligned with shipped behavior

Not done means any of:

- runtime exists only in store APIs but not in control surface
- UI still reads legacy state first
- managed Codex still depends on manual prompt glue for runtime discovery
- multi-tab support is claimed without ownership rules
- schedule/loop behavior is added directly to task truth without a schedule layer

## 13. Blocking Verification Command

No phase may be called complete unless this targeted suite passes with `** TEST SUCCEEDED **`:

```bash
xcodebuild test \
  -project macos/GhoDex.xcodeproj \
  -scheme GhoDex \
  -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY='' \
  -only-testing:GhosttyTests/AITerminalManagerTests \
  -only-testing:GhosttyTests/ControlHarnessTests \
  -only-testing:GhosttyTests/ControlHarnessHostEnvironmentTests \
  -only-testing:GhosttyTests/AgentRuntimeContractsTests
```

Latest recorded pass:

- date: `2026-04-06`
- prerequisite: `zig build -Demit-macos-app=false` was rerun first because this worktree changes `src/config/Config.zig`, and the follow-up serial `xcodebuild test` no longer emitted the stale `ghodex-heartbeat-allow-external-inbox-mutations: unknown field` parser error.
- xcresult: `/Users/leongong/Library/Developer/Xcode/DerivedData/GhoDex-cppxzhjxylyexzayrocpyqoxmalc/Logs/Test/Test-GhoDex-2026.04.06_16-41-34-+0800.xcresult`
- note: the same suite under Xcode parallel test execution produced inconsistent stdout duplication during this rollout, so the authoritative gate evidence remains the serial run above.

## 14. Current Implementation Target

The original P1 -> P5 implementation target for this worktree is complete, including the managed Codex runtime attach path over the existing harness socket.

The next execution target is no longer core runtime construction; it is productization and executor expansion on top of the finished contract:

1. keep all Codex-side runtime mutations on the Control Harness path only as browser / vision executors are added
2. expand browser / vision executors on top of the same runtime task and schedule contract without introducing a second source of truth
3. surface shared queue and schedule controls so multiple Codex tabs remain peer clients of one host-owned runtime
4. preserve multi-tab semantics so additional Codex tabs never become owners of separate queues

Items 1 and 2 are now implemented at the contract layer in this worktree:

- `browser_navigation`, `browser_interaction`, and `vision_automation` are first-class runtime task kinds
- terminal / browser / vision executor requirements are canonicalized into one capability namespace
- managed Codex bootstrap now advertises terminal, browser, and vision executor capabilities on the existing harness-backed runtime path
- Control Harness payload validation now enforces browser / vision request minimums on the same runtime socket contract

The remaining work is no longer contract definition; it is executor productization and shared queue UX on top of the finished runtime boundary.
