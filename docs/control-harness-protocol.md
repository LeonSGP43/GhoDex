# Control Harness Protocol Reference

## Status

`ControlHarness` is the authoritative external control protocol for the current GhoDex desktop app.

This protocol now covers:

- app lifecycle and app state
- workspace / tab / terminal control
- runtime / task / schedule control
- browser automation via `browser.*`
- top-level window control
- panel control
- settings read / stage / validate / apply / reset / diff
- diagnostics metrics, logs, audit, and buffered-event status

Internal adapters still exist, but external callers should target `ControlHarness` only.

## Invocation

Local socket invocation:

```bash
GhoDex +control state.snapshot --socket=/absolute/path/to/harness.sock
```

Examples:

```bash
GhoDex +control app.state.get --socket="$SOCKET"
GhoDex +control window.list --socket="$SOCKET"
GhoDex +control panel.open --panel-id=settings --panel-tab-id=gateway --socket="$SOCKET"
GhoDex +control settings.values.get --socket="$SOCKET"
GhoDex +control settings.apply --payload-json='{"gateway.listen_port":"9527"}' --socket="$SOCKET"
GhoDex +control diagnostics.logs.tail --payload-json='{"source":"audit"}' --socket="$SOCKET"
```

## Command Families

### System and app

- `system.handshake`
- `system.target.resolve`
- `system.capabilities.get`
- `app.state.get`
- `app.relaunch`

### Workspace, tab, and terminal

- `state.snapshot`
- `tab.new`
- `tab.close`
- `tab.rename`
- `terminal.write`
- `terminal.key`
- `terminal.command.run`
- `terminal.read`
- `terminal.snapshot`
- `terminal.semantic`
- `terminal.stream.open`
- `terminal.stream.ack`
- `terminal.close`

### Runtime

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

### Todo

- `todo.snapshot`
- `todo.add`
- `todo.update`
- `todo.complete`
- `todo.assign`
- `todo.syncStale`

### Window and panel

- `window.list`
- `window.focus`
- `window.show`
- `window.hide`
- `window.close`
- `window.tabOverview.toggle`
- `window.floatOnTop.set`
- `panel.list`
- `panel.open`
- `panel.focus`
- `panel.close`
- `panel.tab.select`
- `panel.state.get`

Notes:

- `window.focus` acknowledges the focus/order-front mutation, but `window.list.is_focused`
  and `app.state.get.frontmost_window_number` still depend on macOS making the app active.
  Background-launched isolated debug instances can remain inactive even when the focus
  request succeeds.

Current first-class `panel_id` values:

- `settings`
- `ssh_connections`

Current first-class settings `panel_tab_id` values:

- `general`
- `appearance`
- `gateway`

Current first-class SSH Connections `panel_tab_id` values:

- `connections`
- `todo`
- `learning`
- `taskQueue`
- `browser`
- `preferences`

### Settings

- `settings.schema.get`
- `settings.values.get`
- `settings.values.set`
- `settings.validate`
- `settings.apply`
- `settings.reset`
- `settings.diff`

Settings semantics:

- `settings.values.set` stages a draft only
- `settings.values.get` returns current values plus optional staged draft
- `settings.validate` checks a payload without persisting it
- `settings.apply` persists staged or supplied values to the live app
- `settings.reset` accepts `target=draft|defaults`
- `settings.diff` compares current values with staged or preview values

### Diagnostics

- `diagnostics.metrics.get`
- `diagnostics.metrics.reset`
- `diagnostics.logs.tail`
- `diagnostics.errors.recent`
- `diagnostics.audit.query`
- `diagnostics.eventBuffer.status`

Supported diagnostics log sources:

- `audit`
- `events`
- `runtime`

### Browser

- `browser.tab.*`
- `browser.context.*`
- `browser.page.*`
- `browser.frame.*`
- `browser.dom.*`
- `browser.cookie.*`
- `browser.event.*`
- `browser.prompt.*`
- `browser.download.cancel`

Browser control remains part of the public `ControlHarness` authority even though the app still uses internal Browser IPC adapters under the protocol layer.

## Target Fields

The protocol supports explicit target routing through `target.*` or matching top-level request fields.

Supported routing fields:

- `target.tab_id`
- `target.parent_tab_id`
- `target.terminal_id`
- `target.todo_id`
- `target.subscription_id`
- `target.window_number`
- `target.panel_id`
- `target.panel_tab_id`
- `target.browser_tab_id`
- `target.browser_context_id`
- `target.page_id`
- `target.frame_name`
- `target.task_id`
- `target.schedule_id`
- `target.document_revision`

## Compatibility Policy

Legacy commands are still accepted for compatibility, but new callers should prefer namespaced commands.

Examples:

- `snapshot` -> `state.snapshot`
- `new-tab` -> `tab.new`
- `send-text` -> `terminal.write`
- `send-key` -> `terminal.key`
- `run-command` -> `terminal.command.run`
- `read-terminal` -> `terminal.read`
- `todo-snapshot` -> `todo.snapshot`

`events.subscribe` remains legacy-supported on purpose because it is still the current long-lived stream transport contract. The handle-based replacement path is:

- `events.stream.subscribe`
- `events.stream.drain`
- `events.stream.unsubscribe`

## Logging and Error Surfaces

The protocol exposes real operational diagnostics instead of synthetic placeholders.

Primary artifacts:

- `control-harness-audit.jsonl`
- `control-harness-events.jsonl`
- `runtime-memory-diagnostics.jsonl`

Operational inspection path:

- use `diagnostics.logs.tail` for recent raw log lines
- use `diagnostics.errors.recent` for recent structured error summaries
- use `diagnostics.audit.query` for structured audit records
- use `diagnostics.eventBuffer.status` for buffered event-stream pressure and resync state

## Verification

Primary in-repo verification commands:

```bash
zig build test -Dtest-filter=control
python3 -m py_compile \
  scripts/browser_last_window_close_acceptance.py \
  scripts/control_harness_protocol_surface_live_acceptance.py \
  scripts/control_harness_terminal_v2_live_acceptance.py \
  scripts/control_harness_gateway_transport_live_acceptance.py
```

Live acceptance scripts that exercise the protocol surface:

- `scripts/control_harness_protocol_surface_live_acceptance.py`
- `scripts/control_harness_gateway_transport_live_acceptance.py`
- `scripts/control_harness_terminal_v2_live_acceptance.py`
- `scripts/browser_last_window_close_acceptance.py`
- `scripts/browser_context_protocol_acceptance.py`
- `scripts/browser_runtime_prompt_resolution_acceptance.py`
- `scripts/browser_cookie_persistence_acceptance.py`
- `scripts/browser_popup_event_acceptance.py`
