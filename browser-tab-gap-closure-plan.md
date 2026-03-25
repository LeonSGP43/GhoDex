# Browser Tab Gap Closure Plan

## Goal

Close the remaining gap between "embedded browser that mostly works" and "browser feature safe to merge back to `main` as a durable GhoDex surface".

The target state is not full Chrome product parity. The target state is:

- normal browsing flows work across restarts
- copied or dedicated profiles can preserve user web state durably
- popup and opener flows behave like a normal browser and are externally observable
- the browser does not expose obvious low-effort automation fingerprints created by our own runtime choices
- remaining non-goals are explicit product boundaries, not accidental gaps

## Current Baseline

Current evidence already proves the branch is beyond prototype status:

- external command control works against live browser tabs via `browser.tab.v1`
- popup follow-up routing can stay inside GhoDex and activate the resulting page
- profile-backed state reuse has been demonstrated in earlier branch acceptance work
- the latest post-merge sanity check passed with `zig build -Demit-macos-app=false`

Useful artifacts already produced during this branch:

- popup follow-up visible acceptance: `/tmp/ghx-popup-followup-visible-acceptance.json`
- control-surface proof: `/tmp/ghx-control-proof-b53caadb`

## Workstreams

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

Exit:

- existing popup and control proofs still pass on the merged branch

### Phase 1. Media And Debug Surface

- close H.264 and remote-debug-default questions first
- remove or justify self-inflicted fingerprinting switches

Exit:

- codec/debug audit complete with artifacts

### Phase 2. Profile Service-Surface Closure

- compare Chrome-successful dedicated profile behavior versus GhoDex behavior
- preserve only the web-visible state layers needed for durable login/session reuse

Exit:

- dedicated or mirrored profile can survive restart with expected website session state

### Phase 3. Handler Acceptance Matrix

- run or record every high-value browser-service path

Exit:

- acceptance matrix no longer has unowned gray areas for implemented handlers

### Phase 4. Popup Broker Closure

- expose popup/open-window routing outcomes to external automation

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

- Close self-inflicted parity gaps before chasing broad anti-bot claims. If our own flags or runtime defaults create the anomaly, fix that before blaming CEF or websites.
- Separate Chrome account-service parity from website session parity. The product must preserve website login state; it does not need to impersonate the full Chrome sync stack unless that becomes an explicit requirement.
- Prefer observable broker events over deeper hidden logging. If a popup regression cannot be diagnosed through the external control plane, automation will stay fragile.
- Keep acceptance artifacts durable and named. Browser regressions have already shown that chat-only reasoning is too lossy for later agents.
