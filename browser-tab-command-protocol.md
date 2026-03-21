# Browser Tab Command Protocol

## Purpose

`browser.tab.v1` is the versioned external control contract for GhoDex browser
 tabs. External clients should treat this document as the product-facing API for
 browser control sessions, and treat the internal Swift/CEF implementation as an
 implementation detail.

The protocol is designed for:

- low-latency local control over a running Browser tab
- stable request/response envelopes across transport adapters
- buffered event subscriptions for lifecycle, console, network, and page
  inspection streams
- future adapters that reuse the same contract instead of inventing one-off
  scripts

## Transports

Two local transports currently speak the same request envelope.

### Local IPC Socket

Preferred for long-lived local sessions.

- Path: `~/Library/Application Support/GhoDex/browser-control.sock`
- When `GHODEX_BROWSER_APP_SUPPORT_ROOT` is set for an isolated test session,
  the socket lives under that alternate app-support root instead
- CLI flag: `--transport=ipc`
- CLI default: `--transport=auto` tries IPC first, then falls back to
  AppleScript
- The IPC and CLI Browser control path does not require
  `macos-applescript = true`; that config gate only applies to the AppleScript
  adapter itself
- Response buffering is capped at 1 MiB per connection
- A client that stops draining large responses can be disconnected without
  affecting other active IPC sessions

### AppleScript Adapter

Compatibility path when the IPC socket is unavailable.

- CLI flag: `--transport=applescript`
- App command: `run browser command protocol <requestJSON>`

## Envelope Shape

Every request is a JSON object with this shape:

```json
{
  "id": "B5B5A4DE-1C7E-4B5A-9E8E-5D9C64A0D2C1",
  "version": "browser.tab.v1",
  "command": "listTabs",
  "browserTabID": null,
  "payload": {}
}
```

Field notes:

- `id`: caller-generated UUID used to correlate the response
- `version`: must currently be `browser.tab.v1`
- `command`: one of the supported command names
- `browserTabID`: optional tab identifier; required for tab-specific commands
- `payload`: string-valued map for command arguments

Every response is a JSON object with this shape:

```json
{
  "id": "B5B5A4DE-1C7E-4B5A-9E8E-5D9C64A0D2C1",
  "version": "browser.tab.v1",
  "ok": true,
  "resultJSON": "{\"tabs\":[]}",
  "error": null
}
```

Field notes:

- `ok=true` means the command completed successfully
- `resultJSON` is itself a JSON-encoded string; callers should decode it as a
  second step
- `error` is a structured object when `ok=false`

## Supported Commands

### Tab Discovery and Creation

- `listTabs`
- `newTab`
- `listPages`
- `getActivePage`
- `activatePage`

`listTabs` returns a JSON array of tab summaries:

```json
[
  {
    "id": "browser-tab-1",
    "title": "Example Domain",
    "url": "https://example.com"
  }
]
```

`newTab` returns a single tab summary for the created tab.

`listPages` returns a JSON array of page summaries for one Browser tab:

```json
[
  {
    "id": "E5F4C926-7F1C-466E-A6D9-3A6F6A2F6D4E",
    "title": "Example Domain",
    "url": "https://example.com",
    "isActive": true,
    "documentRevision": 4
  }
]
```

`getActivePage` returns one page summary for the currently selected internal
page.

`activatePage` payload:

```json
{
  "pageID": "E5F4C926-7F1C-466E-A6D9-3A6F6A2F6D4E"
}
```

`activatePage` returns the activated page summary.

### Navigation and Runtime

- `getDebugStatus`
- `loadURL`
- `getCookies`
- `setCookie`
- `deleteCookie`
- `clearCookies`
- `evaluateJavaScript`
- `runDOMBatch`

`getDebugStatus` payload:

```json
{}
```

`getDebugStatus` returns a JSON object with:

- `enabled`: whether the config-gated CEF remote debugging lane is currently enabled
- `port`: the configured remote debugging port when enabled, otherwise `null`
- `source`: currently `config` or `disabled`
- `cefInitialized`: whether global CEF initialization has completed in this app session
- `runtimeAvailable`: whether this app session can see a usable CEF runtime root

## Diagnostics Lane

The optional CEF remote debugging lane is a diagnostics surface, not the
product contract for Browser automation.

- `browser.tab.v1` remains the primary control API for Browser tabs
- Chromium remote debugging stays disabled by default
- enable it only by setting `ghodex-browser-remote-debug-port` to a positive
  local port in config
- use `getDebugStatus` to confirm whether the current app session actually has
  the diagnostics lane enabled before trying any DevTools/CDP workflow
- if the config key is missing or set to `0`, the diagnostics lane is disabled

Example config:

```toml
ghodex-browser-remote-debug-port = 9222
```

`loadURL` payload:

```json
{
  "url": "https://example.com"
}
```

`evaluateJavaScript` payload:

```json
{
  "script": "JSON.stringify({ title: document.title, href: location.href })"
}
```

`getCookies` payload:

```json
{
  "name": "session_id",
  "domain": "example.com",
  "url": "https://example.com/account"
}
```

Payload notes:

- page-targeted commands may include a top-level `pageID` field in the request
  envelope
- when `pageID` is omitted, the command still targets the active page for
  backward compatibility
- when `pageID` is present, it must be a UUID string returned by `listPages`
- all `getCookies` payload fields are optional filters
- `name` matches one visible cookie name exactly
- `domain` matches the current page hostname exactly or by suffix
- `url` matches the active page URL exactly
- the command currently inspects page-visible `document.cookie`, so HTTPOnly
  cookies are intentionally out of scope for `browser.tab.v1`

`getCookies` returns a JSON object with:

- `url`: current page URL
- `domain`: current page hostname
- `cookieHeader`: raw `document.cookie` string
- `appliedFilters`: the normalized non-empty filters that were applied
- `cookies`: decoded `{name,value}` entries after filtering

`setCookie` payload:

```json
{
  "name": "session_id",
  "value": "abc123",
  "path": "/",
  "domain": "example.com",
  "maxAge": "3600",
  "sameSite": "Lax",
  "secure": "true"
}
```

Payload notes:

- `name` is required
- `value` defaults to the empty string when omitted
- `path` defaults to `/`
- `maxAge` must be an integer string when provided
- `sameSite` must be one of `Lax`, `Strict`, or `None`
- `secure` must be `true` or `false` when provided

`deleteCookie` payload:

```json
{
  "name": "session_id",
  "domain": "example.com",
  "path": "/"
}
```

Payload notes:

- `name` is required
- when `path` is omitted, GhoDex tries a small best-effort set of current-page
  path candidates while expiring the cookie

`clearCookies` payload:

```json
{
  "domain": "example.com",
  "path": "/"
}
```

Payload notes:

- all payload fields are optional
- `clearCookies` only clears page-visible cookies from the active page's
  `document.cookie` view
- when `path` is omitted, GhoDex expires each visible cookie across the same
  best-effort current-page path candidates used by `deleteCookie`

`setCookie`, `deleteCookie`, and `clearCookies` return a JSON object with:

- `operation`: `set`, `delete`, or `clear`
- `url`: current page URL
- `domain`: current page hostname
- `cookieHeader`: raw `document.cookie` string after mutation
- `appliedPayload`: the normalized payload GhoDex used for the mutation
- `changedCount`: number of cookie names the command attempted to change
- `changedNames`: cookie names the command targeted
- `cookies`: decoded `{name,value}` entries visible after mutation

### Event Subscription Lifecycle

- `subscribeEvents`
- `drainEvents`
- `unsubscribeEvents`

`subscribeEvents` payload:

```json
{
  "kindsJSON": "[\"consoleMessage\",\"navigationStateChanged\",\"networkRequestFinished\",\"pageInspectionSnapshot\"]"
}
```

`drainEvents` payload:

```json
{
  "subscriptionID": "6B522A3E-0439-4E8F-8E90-55D6C9A4E94C",
  "limit": "50"
}
```

`unsubscribeEvents` payload:

```json
{
  "subscriptionID": "6B522A3E-0439-4E8F-8E90-55D6C9A4E94C"
}
```

## Event Kinds

The external event stream currently supports these `kind` values:

- `consoleMessage`
- `bridgeReady`
- `navigationStateChanged`
- `pageTitleChanged`
- `networkRequestFinished`
- `pageInspectionSnapshot`

### Event Envelope

```json
{
  "id": "C68744A8-B9A6-4BEF-BB4B-4F8066E8F0BF",
  "version": "browser.tab.v1",
  "subscriptionID": "6B522A3E-0439-4E8F-8E90-55D6C9A4E94C",
  "browserTabID": "browser-tab-1",
  "kind": "networkRequestFinished",
  "payload": {
    "pageID": "5C11E4A8-5A79-4E89-B5DA-D0A66F6F3B58",
    "documentRevision": "3",
    "url": "https://example.com/favicon.ico",
    "method": "GET",
    "requestStatus": "success",
    "statusCode": "200",
    "statusText": "OK",
    "mimeType": "image/x-icon",
    "receivedContentLength": "363",
    "isMainFrame": "false",
    "frameName": ""
  },
  "createdAt": "2026-03-19T23:10:00Z"
}
```

### `pageInspectionSnapshot` Payload

`pageInspectionSnapshot` is synthesized from the existing DOM snapshot helper
when a subscribed page becomes ready or finishes a navigation.

Payload keys:

- `pageID`
- `documentRevision`
- `triggerKind`
- `frameName` (when available)
- `ok`
- `snapshotJSON` when `ok=true`
- `errorCode` / `errorMessage` when `ok=false`

`snapshotJSON` decodes into the same `BrowserDOMSnapshotResult` structure used
by the internal Browser control plane.

## CLI Examples

### 1. List live Browser tabs

```bash
ghodex +browser-control --transport=auto --request '{
  "id":"11111111-1111-1111-1111-111111111111",
  "version":"browser.tab.v1",
  "command":"listTabs",
  "payload":{}
}'
```

### 2. Open a new tab and capture the returned `browserTabID`

```bash
ghodex +browser-control --transport=ipc --request '{
  "id":"22222222-2222-2222-2222-222222222222",
  "version":"browser.tab.v1",
  "command":"newTab",
  "payload":{}
}'
```

### 3. Navigate that tab

```bash
ghodex +browser-control --transport=ipc --request '{
  "id":"33333333-3333-3333-3333-333333333333",
  "version":"browser.tab.v1",
  "command":"loadURL",
  "browserTabID":"browser-tab-1",
  "pageID":"E5F4C926-7F1C-466E-A6D9-3A6F6A2F6D4E",
  "payload":{"url":"https://example.com"}
}'
```

### 4. Discover the internal pages inside that Browser tab

```bash
ghodex +browser-control --transport=ipc --request '{
  "id":"44444444-4444-4444-4444-444444444444",
  "version":"browser.tab.v1",
  "command":"listPages",
  "browserTabID":"browser-tab-1",
  "payload":{}
}'
```

### 5. Activate one internal page inside that Browser tab

```bash
ghodex +browser-control --transport=ipc --request '{
  "id":"55555555-5555-5555-5555-555555555555",
  "version":"browser.tab.v1",
  "command":"activatePage",
  "browserTabID":"browser-tab-1",
  "payload":{"pageID":"E5F4C926-7F1C-466E-A6D9-3A6F6A2F6D4E"}
}'
```

### 6. Inspect the current debug-lane status

```bash
ghodex +browser-control --transport=ipc --request '{
  "id":"66666666-6666-6666-6666-666666666666",
  "version":"browser.tab.v1",
  "command":"getDebugStatus",
  "payload":{}
}'
```

### 7. Run a DOM batch

```bash
ghodex +browser-control --transport=ipc --request '{
  "id":"77777777-7777-7777-7777-777777777777",
  "version":"browser.tab.v1",
  "command":"runDOMBatch",
  "browserTabID":"browser-tab-1",
  "pageID":"E5F4C926-7F1C-466E-A6D9-3A6F6A2F6D4E",
  "payload":{
    "commandsJSON":"[{\"id\":\"AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA\",\"command\":\"query\",\"selector\":\"h1\"},{\"id\":\"BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB\",\"command\":\"getDOMSnapshot\",\"selector\":\"body\",\"maxDepth\":2,\"includeText\":true}]"
  }
}'
```

### 8. Inspect page-visible cookies in that tab

```bash
ghodex +browser-control --transport=ipc --request '{
  "id":"88888888-8888-8888-8888-888888888888",
  "version":"browser.tab.v1",
  "command":"getCookies",
  "browserTabID":"browser-tab-1",
  "pageID":"E5F4C926-7F1C-466E-A6D9-3A6F6A2F6D4E",
  "payload":{
    "domain":"example.com"
  }
}'
```

### 9. Subscribe to passive events

```bash
ghodex +browser-control --transport=ipc --request '{
  "id":"99999999-9999-9999-9999-999999999999",
  "version":"browser.tab.v1",
  "command":"subscribeEvents",
  "browserTabID":"browser-tab-1",
  "payload":{
    "kindsJSON":"[\"consoleMessage\",\"navigationStateChanged\",\"networkRequestFinished\",\"pageInspectionSnapshot\"]"
  }
}'
```

### 10. Set a page-visible cookie in that tab

```bash
ghodex +browser-control --transport=ipc --request '{
  "id":"AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
  "version":"browser.tab.v1",
  "command":"setCookie",
  "browserTabID":"browser-tab-1",
  "pageID":"E5F4C926-7F1C-466E-A6D9-3A6F6A2F6D4E",
  "payload":{
    "name":"session_id",
    "value":"abc123",
    "path":"/",
    "sameSite":"Lax"
  }
}'
```

### 11. Clear page-visible cookies in that tab

```bash
ghodex +browser-control --transport=ipc --request '{
  "id":"BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
  "version":"browser.tab.v1",
  "command":"clearCookies",
  "browserTabID":"browser-tab-1",
  "pageID":"E5F4C926-7F1C-466E-A6D9-3A6F6A2F6D4E",
  "payload":{}
}'
```

### 9. Drain buffered events from that subscription

```bash
ghodex +browser-control --transport=ipc --request '{
  "id":"99999999-9999-9999-9999-999999999999",
  "version":"browser.tab.v1",
  "command":"drainEvents",
  "browserTabID":"browser-tab-1",
  "payload":{
    "subscriptionID":"6B522A3E-0439-4E8F-8E90-55D6C9A4E94C",
    "limit":"25"
  }
}'
```

## AppleScript Example

```applescript
set requestJSON to "{\"id\":\"77777777-7777-7777-7777-777777777777\",\"version\":\"browser.tab.v1\",\"command\":\"listTabs\",\"payload\":{}}"
tell application "GhoDex"
    set responseJSON to run browser command protocol requestJSON
end tell
```

## Client Guidance

- always generate a fresh UUID for each request
- treat `resultJSON` as a nested JSON string, not as a pre-decoded object
- `getCookies` currently reflects the page-visible `document.cookie` view, not
  the full Chromium cookie store
- `setCookie`, `deleteCookie`, and `clearCookies` also operate only on the
  page-visible `document.cookie` surface, so they do not touch HTTPOnly cookies
- subscribe once and drain incrementally instead of polling one-off inspection
  commands when you need passive page visibility
- keep draining long-lived IPC sessions; once unread response bytes on one
  connection exceed 1 MiB, GhoDex closes only that connection as backpressure
  protection
- prefer the IPC transport for long-lived local sessions; use AppleScript as a
  compatibility fallback
- treat unknown event kinds and extra payload keys as forward-compatible data,
  not as protocol violations

## Related Documents

- `browser-tab-control-architecture.md`
- `src/cli/browser_control.zig`
- `macos/Sources/Features/Browser/BrowserCommandProtocol.swift`
- `macos/Sources/Features/AppleScript/ScriptBrowserTab.swift`
