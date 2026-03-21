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

### Navigation and Runtime

- `loadURL`
- `getCookies`
- `evaluateJavaScript`
- `runDOMBatch`

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
  "payload":{"url":"https://example.com"}
}'
```

### 4. Run a DOM batch

```bash
ghodex +browser-control --transport=ipc --request '{
  "id":"44444444-4444-4444-4444-444444444444",
  "version":"browser.tab.v1",
  "command":"runDOMBatch",
  "browserTabID":"browser-tab-1",
  "payload":{
    "commandsJSON":"[{\"id\":\"AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA\",\"command\":\"query\",\"selector\":\"h1\"},{\"id\":\"BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB\",\"command\":\"getDOMSnapshot\",\"selector\":\"body\",\"maxDepth\":2,\"includeText\":true}]"
  }
}'
```

### 5. Inspect page-visible cookies in that tab

```bash
ghodex +browser-control --transport=ipc --request '{
  "id":"55555555-5555-5555-5555-555555555555",
  "version":"browser.tab.v1",
  "command":"getCookies",
  "browserTabID":"browser-tab-1",
  "payload":{
    "domain":"example.com"
  }
}'
```

### 6. Subscribe to passive events

```bash
ghodex +browser-control --transport=ipc --request '{
  "id":"66666666-6666-6666-6666-666666666666",
  "version":"browser.tab.v1",
  "command":"subscribeEvents",
  "browserTabID":"browser-tab-1",
  "payload":{
    "kindsJSON":"[\"consoleMessage\",\"navigationStateChanged\",\"networkRequestFinished\",\"pageInspectionSnapshot\"]"
  }
}'
```

### 7. Drain buffered events from that subscription

```bash
ghodex +browser-control --transport=ipc --request '{
  "id":"77777777-7777-7777-7777-777777777777",
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
