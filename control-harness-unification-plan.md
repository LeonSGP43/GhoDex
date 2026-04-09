# Control Harness Unification Plan

## Status
- State: MVP command-surface baseline implemented; verification and migration follow-up remain
- Owner surface: `ControlHarness`
- Date locked: 2026-04-09
- Scope: unify browser, runtime, terminal, tab, and queue/task control under one authoritative protocol layer without collapsing internal modules into one file.

### Current Progress
- Phase 1 routing foundation is complete for the documented MVP command surface.
- `ControlHarness` now advertises and normalizes the catalog MVP command set across system, workspace, terminal, todo, events, and browser namespaces.
- Browser MVP commands route through the `ControlHarness` adapter layer instead of requiring a second public control authority.
- Thin system compatibility commands `system.target.resolve` and `system.capabilities.get` are implemented so callers can inspect the resolved instance and public capability set through the same surface.
- CLI coverage is in place for the namespaced event-stream handle flow: `events.stream.subscribe`, `events.stream.drain`, and `events.stream.unsubscribe` now round-trip as one-shot commands while legacy `events.subscribe` keeps the long-lived socket stream semantics.
- The next work is not to broaden the command table again; it is to finish higher-level verification, client migration, and any remaining post-MVP cleanup under the same authority model.

### Focused Follow-up Landed
- `events.stream.subscribe`, `events.stream.drain`, and `events.stream.unsubscribe` now share one explicit public handle shape: the subscribe acknowledgment returns `stream_id`, and follow-up drain/unsubscribe requests resolve the same buffered event-stream registry inside `ControlHarnessCore`.
- Legacy `events.subscribe` remains unchanged as the long-lived transport/session path.
- The remaining work in this area is verification depth and broader client migration, not protocol redesign.

## Problem Statement
GhoDex currently exposes multiple effective control surfaces:
- `ControlHarness` for terminal/tab/runtime/todo flows
- Browser IPC and `browser-control.sock` for Browser automation
- queue/runtime internals that are testable but not yet consistently framed as one public contract

This creates an authority problem: internal adapters are modular, but the public automation contract is fragmented. The target state is one protocol authority layer: `ControlHarness`.

## Goal
Create one authoritative control protocol for AI control of GhoDex where:
- all officially supported automation commands are addressable through `ControlHarness`
- Browser, runtime, queue/task, terminal, and tab operations remain implemented by their own modules behind the protocol layer
- namespaced commands become the long-term public surface
- legacy commands remain compatible until explicit deprecation
- acceptance tests prove the public contract, not only internal adapters

## Non-Goals
- Do not merge Browser/Terminal/Runtime code into a single implementation file
- Do not remove the internal Browser adapter/runtime adapter mechanisms that the app needs internally
- Do not break legacy clients in this phase
- Do not broaden capability without tests and protocol documentation

## Protocol Authority Rule
`ControlHarness` is the only official external automation authority.

Implications:
- external agents should target `ControlHarness`, not direct Browser sockets or queue storage files
- internal modules may keep private/native entrypoints, but those are implementation details
- any new controllable feature must define its public contract at the `ControlHarness` layer first

## SPAC Constraints
This plan uses the following SPAC constraints for every control feature.

### S - Single authority
- One official automation authority: `ControlHarness`
- No second public control API for the same capability
- Internal adapters must be hidden behind the protocol layer

### P - Protocol first
- Public behavior is defined by request/response schema, command namespace, auth scope, and acceptance tests
- Internal code can vary as long as protocol behavior stays stable

### A - Adapter backed
- Each capability area keeps its own implementation module
- `ControlHarness` performs normalization, validation, authorization, routing, and result framing
- Browser/Runtime/Terminal/Queue modules remain replaceable behind adapters

### C - Checkable
- Every public command requires at least one deterministic verification path
- Changes are not complete until build, targeted tests, and acceptance gates pass

## Command Surface Strategy

### Public namespaced surface
Long-term public surface should prefer namespaced commands such as:
- `system.handshake`
- `state.snapshot`
- `tab.new`
- `tab.close`
- `tab.rename`
- `terminal.write`
- `terminal.key`
- `terminal.run`
- `terminal.read`
- `terminal.snapshot`
- `terminal.semantic`
- `runtime.snapshot`
- `runtime.session.register`
- `runtime.session.heartbeat`
- `runtime.session.release`
- `runtime.task.enqueue`
- `runtime.task.claim`
- `runtime.task.claimNext`
- `runtime.task.update`
- `runtime.task.approve`
- `runtime.task.cancel`
- `runtime.schedule.enqueue`
- `runtime.schedule.update`
- `runtime.schedule.cancel`
- `browser.tab.*`
- `browser.context.*`
- `browser.page.*`
- `browser.frame.*`
- `browser.dom.*`
- `browser.cookie.*`
- `browser.event.*`
- `browser.prompt.*`
- `browser.download.cancel`

### Legacy compatibility rule
Legacy commands remain accepted in this phase and normalize internally to the same routed behavior.
Examples:
- `handshake -> system.handshake`
- `snapshot -> state.snapshot`
- `new-tab -> tab.new`
- `send-text -> terminal.write`
- `agent.runtime.task.claim_next -> runtime.task.claimNext`

## Architecture

### Layer 1: protocol entrypoint
Responsibilities:
- decode request
- normalize aliases
- merge `target` and `options`
- classify command kind
- enforce auth/rate-limit category
- dispatch to module adapter
- return normalized result/error envelope

Primary files:
- `macos/Sources/Features/Control Harness/ControlHarnessCore.swift`
- `macos/Sources/Features/Control Harness/ControlHarnessSupport.swift`
- `macos/Sources/Features/Control Harness/ControlHarnessGateway.swift`
- `macos/Sources/App/macOS/AppDelegate.swift`

### Layer 2: routing/normalization adapter
Responsibilities:
- command alias map
- browser command mapping
- request target/options merge
- browser request construction
- browser result JSON bridging

Primary file:
- `macos/Sources/Features/Control Harness/ControlHarnessCommandRouting.swift`

### Layer 3: capability modules behind the protocol
- Terminal/tab: existing `ControlHarnessCore` terminal/tab handlers
- Runtime/task/queue: existing runtime store and related task/schedule handlers
- Browser: `ScriptBrowserTab.routeExternalCommand(...)` adapter path

## Functional Requirements

### Terminal and tab management
Must support through `ControlHarness`:
- create tab
- close tab
- rename tab
- send text
- send key
- run command
- read terminal
- terminal snapshot v2
- terminal semantic v2
- terminal stream open/ack
- close terminal

### Runtime and queue/task management
Must support through `ControlHarness`:
- runtime snapshot
- session register/heartbeat/release
- task enqueue/claim/claimNext/update/approve/cancel
- schedule enqueue/update/cancel

### Browser control
Must support through `ControlHarness`:
- list/create contexts and tabs/pages
- load URL
- basic DOM query/click/type/eval
- event subscribe/drain/unsubscribe
- popup/dialog/cookie related commands

## Security and Gateway Requirements
- handshake remains unauthenticated when configured that way today
- observe vs mutate scopes must stay correct after normalization
- Browser queries map to observe scope
- Browser mutations map to mutate scope
- Browser event subscribe/drain/unsubscribe must be rate-limited in the resync class
- Browser input commands such as click/type must be rate-limited in the input class

## Acceptance Criteria
Implementation is accepted only when all of the following are true.

### Contract
- `ControlHarnessCore.supportedCommands` advertises legacy + namespaced + browser commands
- namespaced requests normalize to legacy/internal routed behavior without behavioral drift
- Browser commands execute through `ControlHarness` instead of requiring a second public control authority

### Backward compatibility
- existing legacy command tests remain green
- socket handshake still returns legacy runtime command set
- legacy transport behavior for `events.subscribe` and `terminal.stream.open` remains unchanged

### Browser integration
- `browser.tab.list` and at least one page/DOM command are routable via `ControlHarness`
- Browser result payloads are returned as valid JSON envelopes
- Browser command classification is correct for query/mutation/rate-limit/auth handling

### Runtime/queue coverage
- runtime session lifecycle and runtime snapshot socket tests remain green
- task/schedule commands still validate and round-trip correctly after normalization changes

## Test Matrix

### Unit / focused Swift tests
- alias normalization for namespaced commands
- `target` and `options` merge behavior
- browser adapter request mapping
- browser command kind classification
- gateway policy still applies to normalized terminal mutations
- handshake advertises namespaced and browser commands

### Focused control harness tests
- `ControlHarnessTests/runtimeHandshakeAdvertisesCommandsOverControlHarnessSocket()`
- `ControlHarnessTests/runtimeSessionLifecycleWorksOverControlHarnessSocket()`
- runtime task/schedule roundtrip tests already covering `agent.runtime.*`

### Live/acceptance gates to keep green
- `scripts/control_harness_gateway_transport_live_acceptance.py`
- `scripts/control_harness_terminal_v2_live_acceptance.py`
- `scripts/browser_context_protocol_acceptance.py`
- `scripts/browser_runtime_prompt_resolution_acceptance.py`
- `scripts/browser_cookie_persistence_acceptance.py`
- `scripts/browser_popup_event_acceptance.py`

## Rollout Phases

### Phase 1 - routing foundation
- add normalized command aliases
- add request target/options merge
- expose browser command adapter behind `ControlHarness`
- keep legacy commands working
- Status on 2026-04-09: complete for the documented MVP command catalog

### Phase 2 - gateway alignment
- make auth scope and rate-limit category normalization aware
- make app delegate request routing normalize before policy decisions
- preserve long-lived subscription transport semantics only for actual harness streams
- Status on 2026-04-09: command routing and event-stream handle follow-up are implemented; policy/gateway hardening remains a separate lane

### Phase 3 - test and acceptance expansion
- add focused Swift tests for alias and browser mapping
- confirm key socket tests still pass
- run Browser/ControlHarness acceptance gates
- Status on 2026-04-09: focused Swift/Zig coverage now includes the namespaced event-stream handle lifecycle; broader live acceptance remains pending

### Phase 4 - public migration follow-up
- migrate docs and clients toward namespaced commands
- keep legacy aliases until explicit deprecation window is announced
- eventually retire direct public Browser socket guidance in favor of `ControlHarness`

## Completion Gates
Implementation is complete only if all gates pass.

1. `nu macos/build.nu --scheme GhoDex --configuration Debug --action build`
2. Focused `ControlHarnessTests` pass for new normalization/browser coverage
3. Existing runtime socket lifecycle tests pass
4. No known failing targeted test remains in the touched area
5. The plan file stays aligned with shipped behavior

## 2026-04-09 Evidence Snapshot
- `xcodebuild build-for-testing -project macos/GhoDex.xcodeproj -scheme GhoDex -destination 'platform=macOS' -only-testing:GhosttyTests/ControlHarnessCommandRoutingTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=''`
- `xcodebuild test-without-building -xctestrun /Users/leongong/Library/Developer/Xcode/DerivedData/GhoDex-agcunbrxnmmsbjbkneezzlhlgjed/Build/Products/GhoDex_GhoDex_macosx26.2-arm64.xctestrun -destination 'platform=macOS' -only-testing:GhosttyTests/ControlHarnessCommandRoutingTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=''`
- `zig build test -Dtest-filter='parse control terminal command run alias arguments'`
- `zig build test -Dtest-filter='events.stream.subscribe streams ack before live event when replay is empty'`
- `zig build test -Dtest-filter='parse control system target resolve alias'`
- `zig build test -Dtest-filter='parse control system capabilities get alias'`
- `git diff --check -- 'src/cli/control.zig' 'macos/Sources/Features/Control Harness/ControlHarnessCommandRouting.swift' 'macos/Sources/Features/Control Harness/ControlHarnessCore.swift' 'macos/Tests/ControlHarness/ControlHarnessCommandRoutingTests.swift'`

## Initial Commit Slicing Rule
When committing this work, keep atomic boundaries:
1. routing + protocol normalization foundation
2. browser-through-control-harness behavior/tests
3. docs/plan or CLI surface changes if independent

## Current Landing Notes
This implementation phase specifically lands:
- namespaced alias normalization in `ControlHarness`
- browser routing through `ControlHarness`
- gateway/auth/rate-limit normalization updates
- focused tests proving alias/browser contract behavior
