# Browser Tab Control Architecture

## Goal

Design the embedded CEF browser tabs as a first-class, command-addressable
browser runtime that can be controlled with low latency, low overhead, and a
stable product API.

The control plane must:

- keep the default execution path inside the existing app and CEF processes
- avoid coordinate-click and Accessibility-driven automation as the primary path
- support precise page, tab, and frame targeting
- expose a durable command API that remains stable even if the internal browser
  plumbing evolves
- keep optional deep diagnostics available without making them the product's
  main runtime dependency

## Architecture Decision

Use a bridge-first architecture:

- Primary control path: typed native control plane plus renderer page agent
- Diagnostics path: optional CDP / remote debugging for developer-only sessions
- Fallback path: native input synthesis only when semantic DOM commands are not
  sufficient

Do not make remote debugging, Playwright attach, coordinate clicks, or
Accessibility scripting the default browser-control mechanism.

## Module Boundaries

### 1. Browser Control API

Swift-facing typed protocol that every higher-level caller uses.

Responsibilities:

- define command, response, event, and error contracts
- route requests to the correct browser page
- expose one durable API surface for future CLI, AppleScript, agent, and IPC
  adapters
- version the command protocol independently from CEF internals

Suggested home:

- `macos/Sources/Features/Browser/BrowserTabModel.swift` for the initial
  skeleton
- later extract to `BrowserControlPlane.swift` once the API grows

### 2. Browser Page Bridge

Swift/AppKit bridge per page tab.

Responsibilities:

- own page-local closures for navigation and page commands
- translate typed control requests into CEF view calls
- cancel requests when a page is removed

Current insertion point:

- `macos/Sources/Features/Browser/BrowserTabView.swift`

### 3. Native CEF View Bridge

Objective-C++ boundary around `CefBrowser` and `CefFrame`.

Responsibilities:

- create and own the native browser instance
- execute page commands on the correct CEF thread
- surface CEF lifecycle and console events into Swift
- marshal request/response traffic between browser and renderer processes

Current insertion point:

- `macos/Sources/Features/Browser/CEF/GhoDexCEFBridge.h`
- `macos/Sources/Features/Browser/CEF/GhoDexCEFBridge.mm`

### 4. Renderer Page Agent

JavaScript-side agent injected into each page context.

Responsibilities:

- run DOM queries and semantic actions
- collect structured snapshots and targeted analysis payloads
- implement `waitFor` with observers instead of native polling
- return structured JSON payloads rather than raw string dumps when possible

Initial implementation note:

- phase one can support fire-and-forget JS execution plus a typed result channel
- richer selector, DOM, console, and observer APIs can layer on top after the
  transport is stable

### 5. Optional Debug Lane

Developer-only diagnostics.

Responsibilities:

- expose optional CDP / remote debugging for deep debugging sessions
- stay off by default in normal browser-tab sessions
- never become the main product API contract

## Control Protocol

### Target Model

Every command targets a specific browser page and can optionally scope itself to
one frame.

Core target fields:

- `pageID`
- `frameName` or a future `frameID`
- `documentRevision`

`documentRevision` prevents stale responses from an old navigation from being
applied to a new page state.

### Request Contract

Suggested request shape:

```text
requestID
target
command
payload
timeoutMS
issuedAt
```

Command families:

- Navigation: `loadURL`, `goBack`, `goForward`, `reload`
- Runtime: `executeJavaScript`, `evaluateJavaScript`
- DOM: `query`, `queryAll`, `click`, `type`, `focus`, `scrollIntoView`
- Wait/observe: `waitForSelector`, `waitForDocumentReady`, `observeMutations`
- Inspect: `getDOMSnapshot`, `getText`, `getAttributes`, `getBoundingBox`

### Response Contract

Suggested response shape:

```text
requestID
target
stateRevision
completedAt
valueJSON
error
```

Rules:

- every request resolves exactly once
- page close, navigation reset, and bridge teardown all resolve pending
  requests with a structured error
- large structured values should be returned as JSON strings or typed envelopes,
  not ad-hoc console text

## Event Model

The control plane should support subscription-style events instead of frequent
 polling.

Event families:

- `lifecycle.pageCreated`
- `lifecycle.pageClosed`
- `lifecycle.navigationCommitted`
- `lifecycle.loadStateChanged`
- `runtime.consoleMessage`
- `runtime.javaScriptError`
- `runtime.bridgeReady`
- `inspect.domMutated`
- `network.requestStarted`
- `network.requestFinished`

The first skeleton only needs event types and ownership boundaries. Full event
delivery can land after the command transport is in place.

## Error Model

Every failure should return a typed code plus a human-readable message.

Core error codes:

- `pageNotFound`
- `bridgeUnavailable`
- `browserNotReady`
- `frameNotFound`
- `invalidRequest`
- `commandUnsupported`
- `navigationReplacedRequest`
- `requestTimedOut`
- `pageClosed`
- `internalFailure`

Error requirements:

- errors must be serializable
- every error must indicate whether retrying is reasonable
- errors caused by page lifecycle changes should include the last known page
  revision

## Performance Rules

- prefer semantic DOM commands over synthesized input
- keep command dispatch inside the app and CEF processes by default
- use observer-driven waits in the page agent instead of native polling loops
- support batched operations so related DOM actions can run in a single bridge
  round-trip
- keep request routing page-local so multiple tabs can run commands in parallel
  without fighting over global state

## Security and Product API Notes

- treat raw JavaScript execution as an internal power tool, not the main public
  automation API
- prefer higher-level commands for external callers so the product API stays
  stable even if the renderer agent evolves
- if browser control is exposed to AppleScript, CLI, or future IPC, route every
  caller through the same typed control plane

## Phased Implementation Plan

### Phase 1: Skeleton

- [ ] add typed request, response, event, and error types in Swift
- [ ] add page-level bridge routing in `BrowserTabModel`
- [ ] extend `GhoDexCEFView` with JS execution entry points
- [ ] keep unsupported commands returning structured errors instead of silent
      no-ops

### Phase 2: Transport

- [ ] add request IDs, timeout handling, and pending-request cancellation
- [ ] add browser-to-renderer message transport for structured results
- [ ] invalidate pending commands on page close and top-level navigation resets

### Phase 3: Page Agent

- [ ] inject a renderer page agent with selector and DOM helpers
- [ ] implement `query`, `click`, `type`, and `waitForSelector`
- [ ] expose structured DOM snapshots and console streams

### Phase 4: Adapters

- [ ] add one internal command entry point that future CLI and AppleScript
      adapters can call
- [ ] expose browser-specific scripting verbs without leaking raw renderer
      internals into every caller
- [ ] keep the external client contract documented in
      `browser-tab-command-protocol.md` as commands and event kinds evolve

### Phase 5: Optional Debug Lane

- [ ] add config-gated remote debugging
- [ ] keep CDP off by default
- [ ] document CDP as diagnostics, not as the product API contract

## Atomic Commit Roadmap

1. `docs(browser): record browser tab control architecture`
2. `feat(browser): add browser control-plane skeleton`
3. `feat(cef): add request-response JS execution transport`
4. `feat(browser): add page-agent DOM command primitives`
5. `feat(browser): add browser inspection events and subscriptions`
6. `feat(debug): add optional CDP diagnostics lane`

## Decision Trail

- The default control surface should remain inside the app's existing CEF
  instance because that keeps the command path short and avoids making the
  browser appear externally attached by default.
- A typed control plane is more durable than exposing raw JS or CDP as the main
  product API because it decouples external callers from renderer and Chromium
  implementation details.
- CDP remains valuable, but as a diagnostics lane rather than the foundation of
  the browser-tab product contract.
