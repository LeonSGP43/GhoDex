# Browser Tab Gap Closure Plan

## Goal

Close the remaining gap between "embedded browser that mostly works" and "browser feature safe to merge back to `main` as a durable GhoDex surface".

The target state is not full Chrome product parity. The target state is:

- normal browsing flows work across restarts
- copied or dedicated profiles can preserve user web state durably
- popup and opener flows behave like a normal browser and are externally observable
- the browser does not expose obvious low-effort automation fingerprints created by our own runtime choices
- remaining non-goals are explicit product boundaries, not accidental gaps

Browser Context transition note:

- the control-plane top-level object is now being formalized as `browserContext`
  rather than reusing the overloaded Browser tab/window term
- the current Browser tab controller remains the UI container during the
  transition, but new protocol and acceptance work should describe top-level
  isolation and lifecycle in terms of context/page/frame boundaries

## Execution Rule

All remaining work on this plan must follow atomic development rules.

- one task at a time: do not mix two plan tasks in one implementation slice
- before starting the next task, finish the current task end-to-end:
  implementation, durable docs, tests or acceptance evidence, and verification
- if a task changes behavior, update the relevant protocol/runtime/design docs in
  the same atomic change
- if a task cannot yet be covered by an automated test, record the exact
  acceptance procedure and evidence path before marking it complete
- do not begin the next phase until the current phase has a clear close-out with
  code, documentation, and verification artifacts

## Current Baseline

Current evidence already proves the branch is beyond prototype status:

- external command control works against live browser tabs via `browser.tab.v1`
- popup follow-up routing can stay inside GhoDex and activate the resulting page
- profile-backed state reuse has been demonstrated in earlier branch acceptance work
- the latest post-merge sanity check passed with `zig build -Demit-macos-app=false`

Useful artifacts already produced during this branch:

- popup follow-up visible acceptance: `/tmp/ghx-popup-followup-visible-acceptance.json`
- control-surface proof: `/tmp/ghx-control-proof-b53caadb`
- Browser teardown crash report: `/Users/leongong/Library/Logs/DiagnosticReports/GhoDex-2026-03-26-152602.ips`

## Workstreams

### 0. BrowserTab Teardown Stability

Problem:
The current BrowserTab teardown path can abort the app on the main thread during
SwiftUI view dismantle. The crash report from March 26, 2026 points to
`BrowserCEFDeckView.Coordinator.reset(from:)` calling
`BrowserTabModel.unbindBridge(for:)`, which then writes the `@Published`
`BrowserPageState.isControlBridgeReady` flag while SwiftUI/Combine is already
invalidating the same observable object graph.

Key evidence:

- crash thread: `CrBrowserMain` / `com.apple.main-thread`
- termination: `SIGABRT`
- runtime path: `swift_beginAccess` -> `Published.subscript.setter` ->
  `BrowserPageState.isControlBridgeReady.setter`
- source chain:
  `BrowserTabView.swift:299` ->
  `BrowserTabModel.swift:923` ->
  `BrowserTabModel.swift:595`

Deliverables:

- remove synchronous `@Published` mutation from the Browser view dismantle path
- choose one durable fix and record the decision near the implementation:
  - defer `unbindBridge` work out of `dismantleNSView/reset`
  - or stop mutating `isControlBridgeReady` during bridge teardown
  - or move bridge-readiness bookkeeping to non-`@Published` internal state
- add a narrow regression test or deterministic repro harness if practical
- record the crash root cause and fix boundary in Browser durability docs so
  later agents do not misattribute the failure to CEF worker threads

Acceptance:

- repeated Browser tab/context close and page teardown no longer crash the app
- no `swift_beginAccess` / exclusivity abort appears in the teardown repro path
- Browser bridge teardown still leaves page/control routing in a clean state
- the fix does not regress page close, context close, or popup follow-up cleanup

Close-out evidence in this worktree:

- implementation:
  `macos/Sources/Features/Browser/BrowserTabModel.swift`
  `macos/Sources/Features/AppleScript/ScriptBrowserTab.swift`
- deterministic repro + regression harness:
  `scripts/browser_teardown_stability_acceptance.py`
- passing acceptance artifact:
  `/tmp/ghx-browser-teardown-stability-acceptance.json`
- status:
  closed for this worktree; the March 26, 2026 `swift_beginAccess` teardown
  abort no longer reproduces in the repeated context/page close harness
  backed by the artifact above

### 0.5 Browser Last-Window Close Semantics

Problem:
The current Browser UI container is still a top-level `NSWindowController`, so
closing the last Browser window can accidentally terminate the whole app when
`quit-after-last-window-closed = true` is enabled. That violates the intended
product boundary: closing Browser should close that Browser surface, not quit
GhoDex.

Deliverables:

- classify the last closed top-level window as Browser, Terminal, or Other
- route `applicationShouldTerminateAfterLastWindowClosed(_:)` through a small
  policy layer instead of directly returning the raw config flag
- keep Terminal last-window behavior unchanged
- treat dedicated Browser popup windows as Browser-owned closes too
- add a deterministic regression test for the policy and controller
  classification

Acceptance:

- closing the last Browser window/controller no longer terminates the app
- closing the last Terminal window still honors `quit-after-last-window-closed`
- Browser popup windows do not reintroduce the quit-on-close bug through a
  separate controller class

Close-out evidence in this worktree:

- implementation:
  `macos/Sources/App/macOS/AppDelegate.swift`
  `macos/Sources/App/macOS/LastWindowCloseTerminationPolicy.swift`
- regression tests:
  `macos/Tests/LastWindowCloseTerminationPolicyTests.swift`
- passing verification:
  `nu macos/build.nu --configuration Debug --action build`
  `xcodebuild -project macos/GhoDex.xcodeproj -scheme GhoDex -destination 'platform=macOS,arch=arm64' test -only-testing:GhosttyTests/LastWindowCloseTerminationPolicyTests`
- status:
  closed for this worktree; Browser-owned top-level closes no longer route into
  app termination, while Terminal last-window closes still follow the config
  gate
- note:
  a higher-level window-close acceptance harness was drafted in
  `scripts/browser_last_window_close_acceptance.py`, but end-to-end AppleScript
  driving is currently blocked by the Debug app's broken scripting dictionary
  (`osascript` returns `-2705`), so the durable evidence for this slice is the
  product build plus the new policy regression tests

### 1. Media And Fingerprint Parity

Problem:
The browser is still not ready to claim "normal long-term browser" status while codec and fingerprint surfaces are under-audited, especially H.264 and related video playback capability.

Deliverables:

- a concrete capability inventory for `HTMLMediaElement`, MSE, WebRTC codec negotiation, canvas, WebGL, WebGPU, UA/client hints, and remote debug exposure
- explicit evidence for H.264 playback on a local deterministic page and at least one real site path
- a list of browser-launch flags or runtime overrides that create self-inflicted fingerprint anomalies
- a keep/remove decision for each non-default runtime switch currently applied in managed, direct, and mirror modes

Acceptance:

- a deterministic local codec page proves whether H.264 decode works in this app build
- `navigator.mediaCapabilities`, media error states, and actual playback results are archived
- remote debug is proven closed by default and only open when explicitly configured
- the resulting audit distinguishes "platform/build limitation" from "our own bad defaults"

### 2. External And Mirror Service Surface

Problem:
`direct` and `mirror` modes still intentionally strip or disable part of Chrome's broader service layer. Some of that is correct product scoping, but some of it may be the reason a copied profile behaves differently from Chrome after restart.

Deliverables:

- a service-surface inventory for cookies, `Network/Cookies`, local storage, IndexedDB, service workers, Cache Storage, permissions, push/GCM-adjacent state, login DBs, os_crypt/keychain path, and profile-level preference stores
- a table that marks each service as `preserve`, `rewrite`, `drop`, or `non-goal`
- an explicit product decision for Chrome-only account/sync/signin state versus plain website login/session state
- a restart acceptance lane using one dedicated profile where a manual login once is acceptable but subsequent restarts must preserve session state

Acceptance:

- same copied or dedicated profile can log in once, restart GhoDex, and stay logged in on the target site
- mirror mode does not require the source Chrome app to be closed when using an already-created mirror snapshot
- any required degradation is documented as product boundary, not discovered accidentally during runtime

### 3. Missing End-To-End Acceptance

Problem:
Several handler surfaces are code-complete enough to compile but still lack durable end-to-end evidence. That means merge confidence is still too dependent on source inspection.

Minimum matrix to close:

- file chooser
- download flow
- JavaScript alert / confirm / prompt
- permission request flow
- HTTP auth
- certificate error handling
- popup / opener / self-close
- open-in-new-tab versus open-in-new-window disposition behavior

Deliverables:

- `browser-tab-acceptance-matrix.md` updated so every implemented handler is either backed by an artifact or explicitly marked unproven
- deterministic acceptance scripts where practical
- manual-only steps called out only when automation would be misleading or disproportionately expensive

Acceptance:

- every handler surfaced in `GhoDexCEFBridge.mm` and related Swift routing has either passing evidence or an explicit red status
- no handler remains in the ambiguous state of "implemented somewhere, probably works"

### 3.5 Runtime Service Event Surface

Problem:
The CEF layer already handles downloads, JS dialogs, permission prompts, HTTP
auth, and certificate warnings, but the external Browser control plane still
cannot observe those flows as first-class events. That leaves automation blind
exactly where real browser/runtime regressions are hardest to diagnose.

Deliverables:

- extend the external event stream so runtime-service flows are observable
  without private logs
- add stable event kinds for:
  - download lifecycle
  - JavaScript dialog lifecycle
  - permission request lifecycle
  - HTTP auth lifecycle
  - certificate warning lifecycle
- keep the first atomic slice to observability only; interactive resolve/cancel
  commands remain a follow-up once the typed event model is stable
- add unit coverage for broker kind mapping and payload contract stability

Acceptance:

- `subscribeEvents` can request the new runtime-service event kinds
- the CEF-to-Swift path emits typed Browser control events for the five runtime
  surfaces above
- the external broker forwards those events with stable payload keys and page
  targeting metadata
- the acceptance matrix no longer treats these handler surfaces as "implemented
  but externally invisible"

### 3.6 Runtime Prompt Resolution Control

Problem:
Observability alone is not enough for real automation. JS dialogs, permission
prompts, HTTP auth challenges, and certificate warnings still resolve only
through native AppKit UI, which means the external Browser control plane can
see the pause but cannot continue it. That keeps OAuth, login, and certificate
triage flows partially manual even though the runtime already has typed
handlers.

Deliverables:

- add external commands for:
  - `resolveDialog`
  - `resolvePermission`
  - `resolveAuth`
  - `resolveCertificate`
- assign a stable `requestID` to each externally visible runtime prompt event
- route resolve commands to the actual paused CEF callback rather than DOM
  scripting or synthetic UI clicks
- preserve normal browser usability by allowing native fallback UI when no
  external resolution arrives within a short grace window
- add unit coverage for request parsing, payload shape, and event contract

Acceptance:

- requested runtime prompt events expose a stable `requestID`
- a matching resolve command can complete the paused CEF handler through IPC and
  AppleScript entrypoints
- invalid or stale `requestID` values fail as typed control errors instead of
  silently no-oping
- unresolved prompts still remain usable through native browser UI after the
  external grace window expires
- teardown clears pending prompt state without leaking callbacks into later page
  lifecycles

### 4. Popup And Open-Window Observability

Problem:
Popup and open-window behavior is much better now, but automation visibility is still too weak. The external broker should expose intent and outcome, not just final page state.

Deliverables:

- broker events for popup/new-window intent including source page ID, requested URL, disposition, user gesture, and follow-up routing target
- resulting page or window identity in the emitted event payload
- activation and visibility state in the final event so automation can verify "user would have seen this"
- a clear mapping between low-level popup events and externally visible `browser.tab.v1` state transitions

Acceptance:

- an isolated popup acceptance can assert not only that `popup2` exists, but exactly where it routed and whether it became active
- external automation can diagnose popup regressions without attaching DevTools or reading private logs

## Sequencing

### Phase 0. Preserve The Known-Good Baseline

- keep current popup/control/profile proofs reproducible after the `main` sync
- avoid reopening already-closed routing issues while working on new gaps
- close the BrowserTab teardown exclusivity crash before deeper Browser Context
  refactors so the control-plane lifecycle remains stable during later work
- treat the crash fix itself as one atomic unit:
  root-cause doc -> implementation -> regression test or acceptance repro ->
  verification -> only then move on

Exit:

- existing popup and control proofs still pass on the merged branch
- Browser teardown no longer aborts in the known `isControlBridgeReady`
  dismantle path
- teardown fix has durable documentation plus a reproducible verification path

### Phase 1. Media And Debug Surface

- close H.264 and remote-debug-default questions first
- remove or justify self-inflicted fingerprinting switches
- finish media/debug docs and evidence before starting profile service-surface
  closure

Exit:

- codec/debug audit complete with artifacts

### Phase 2. Profile Service-Surface Closure

- compare Chrome-successful dedicated profile behavior versus GhoDex behavior
- preserve only the web-visible state layers needed for durable login/session reuse
- finish profile docs and restart acceptance before starting handler-surface work

Exit:

- dedicated or mirrored profile can survive restart with expected website session state

### Phase 3. Handler Acceptance Matrix

- run or record every high-value browser-service path
- finish the acceptance matrix and evidence set before starting popup broker
  closure
- close runtime prompt resolve control before claiming handler-surface
  completeness for the interactive prompt subset

Exit:

- acceptance matrix no longer has unowned gray areas for implemented handlers

### Phase 4. Popup Broker Closure

- expose popup/open-window routing outcomes to external automation
- finish protocol docs and popup evidence before declaring the plan complete

Exit:

- popup regressions become externally diagnosable without internal logging

## Merge Gate

The branch is mergeable back to `main` only after all of the following are true:

- `main` sync stays build-green
- browser control proof still passes
- popup follow-up proof still passes
- media/debug audit is complete
- profile restart persistence is proven on a dedicated or mirrored profile
- implemented handler surfaces are backed by acceptance evidence
- popup/open-window routing is externally observable enough for automation triage

Until then, the branch should be treated as conditionally mergeable for continued browser work, not as "browser completeness achieved".

## Decision Trail

- Fix the BrowserTab teardown crash before adding more lifecycle complexity. A
  first-class Browser Context model increases object churn around page/context
  creation and destruction, so leaving a known Swift exclusivity abort in the
  teardown path would make later isolation work harder to diagnose.
- Close self-inflicted parity gaps before chasing broad anti-bot claims. If our own flags or runtime defaults create the anomaly, fix that before blaming CEF or websites.
- Separate Chrome account-service parity from website session parity. The product must preserve website login state; it does not need to impersonate the full Chrome sync stack unless that becomes an explicit requirement.
- Prefer observable broker events over deeper hidden logging. If a popup regression cannot be diagnosed through the external control plane, automation will stay fragile.
- Keep acceptance artifacts durable and named. Browser regressions have already shown that chat-only reasoning is too lossy for later agents.
