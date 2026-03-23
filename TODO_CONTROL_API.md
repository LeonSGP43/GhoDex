# Todo Control API

This document describes the native Todo control surface exposed by the running GhoDex app through the control harness and the `ghodex +control` CLI.

## Purpose

Use this API when an external program needs to operate the real in-app todo system instead of editing date JSON files directly. These commands talk to the same store and pointer-resolution logic used by the macOS UI, so carry-forward pointers, completion state, and workspace assignment all behave consistently with the app.

## Preconditions

- A GhoDex app instance must already be running.
- The app's native control harness socket must be reachable.
- For CLI usage, use the same build of `ghodex` that matches the running app when possible.

Debug test app path:

```text
/Users/leongong/Desktop/LeonProjects/gho_workspace/wt-macos-todolist-picker-opus-20260320/macos/build/Debug/GhoDex.app
```

## Transport Options

### Preferred: `ghodex +control`

Use the CLI for most automation. It handles:

- request JSON encoding
- socket discovery
- one-shot response printing
- machine-readable exit status

### Raw socket protocol

The app also accepts one JSON request per socket connection over the native Unix-domain control socket. Requests and responses use snake_case keys such as `request_id`, `todo_id`, `workspace_id`, and `include_completed`.

## Socket Resolution

By default, `ghodex +control` tries to find a reachable control harness socket for:

- `com.leongong.ghodex.debug`
- `com.leongong.ghodex`

You can override resolution with either:

- `--socket <absolute socket path>`
- `GHODEX_CONTROL_SOCKET=<absolute socket path>`

## Request Envelope

All requests follow the same high-level shape:

```json
{
  "request_id": "req_001",
  "protocol_version": "1.0",
  "command": "todo-snapshot",
  "client": "my-automation",
  "idempotency_key": "optional-mutation-key"
}
```

Common fields:

- `request_id`: required logical request identifier.
- `protocol_version`: optional. Current protocol is `1.0`.
- `command`: required command name.
- `client`: optional caller label. The CLI defaults this to `ghodex-cli`.
- `idempotency_key`: optional for mutations. Reusing the same key with the same mutation payload returns the cached result; reusing it with different mutation parameters returns an `idempotency_conflict`.

## Response Envelope

Every one-shot response is wrapped in:

```json
{
  "request_id": "req_001",
  "status": "ok",
  "result": { "...": "..." },
  "error_code": null,
  "error_message": null
}
```

When `status` is `error`, `result` is omitted and `error_code` plus `error_message` explain the failure.

## Workspace ID Discovery

Todo assignment uses the app's workspace tab UUID, not a separate todo-only ID.

Practical ways to get a workspace ID:

- Read the regular control-harness `snapshot` response and use a tab's `tab_id`.
- Reuse a workspace ID you previously received from another control-harness automation flow.

For assignment purposes, `workspace_id` maps to the top-level tab/workspace represented in the UI.

## Todo Item Semantics

The Todo API can return two kinds of rows:

- Normal rows: `is_carry_forward_pointer = false`
- Carry-forward pointers: `is_carry_forward_pointer = true`

Important pointer behavior:

- `todo-update`, `todo-complete`, and `todo-assign` resolve carry-forward pointers back to the original source item.
- `todo-sync-stale` creates new pointer rows in the target day instead of cloning historical unfinished tasks into disconnected copies.

## Command Reference

### `todo-snapshot`

Returns the todo list snapshot for a day.

Flags:

- `--date=YYYY-MM-DD` optional, defaults to today
- `--include-completed=true|false` optional, defaults to `true`

CLI example:

```bash
ghodex +control todo-snapshot --date=2026-03-23 --include-completed=false
```

Raw JSON example:

```json
{
  "request_id": "req_snapshot_001",
  "protocol_version": "1.0",
  "command": "todo-snapshot",
  "date": "2026-03-23",
  "include_completed": false,
  "client": "todo-bot"
}
```

Returns:

- The day snapshot directly in `result`

### `todo-add`

Creates a new todo item for a day.

Flags:

- `--title=<text>` required
- `--notes=<text>` optional
- `--date=YYYY-MM-DD` optional, defaults to today
- `--idempotency-key=<key>` recommended for retryable automation

CLI example:

```bash
ghodex +control todo-add \
  --title="Call design review" \
  --notes="Bring timeline mock" \
  --date=2026-03-23 \
  --idempotency-key=todo-add-call-design-review-2026-03-23
```

Raw JSON example:

```json
{
  "request_id": "req_add_001",
  "command": "todo-add",
  "date": "2026-03-23",
  "title": "Call design review",
  "notes": "Bring timeline mock",
  "idempotency_key": "todo-add-call-design-review-2026-03-23"
}
```

Returns:

- mutation envelope with `operation = "todo-add"`
- `mutated_todo_id`
- a fresh post-mutation `snapshot`

### `todo-update`

Updates the title and/or notes of an existing visible todo row.

Flags:

- `--todo-id=<uuid>` required
- `--title=<text>` optional
- `--notes=<text>` optional
- `--date=YYYY-MM-DD` optional, defaults to today
- `--idempotency-key=<key>` optional

Rules:

- At least one of `--title` or `--notes` must be provided.
- Validation rejects empty effective titles.
- When the target row is a carry-forward pointer, the mutation is applied back to the source item.

CLI example:

```bash
ghodex +control todo-update \
  --todo-id=01234567-89AB-CDEF-0123-456789ABCDEF \
  --notes="Updated after QA pass"
```

### `todo-complete`

Marks a todo complete or incomplete.

Flags:

- `--todo-id=<uuid>` required
- `--completed=true|false` required
- `--date=YYYY-MM-DD` optional, defaults to today
- `--idempotency-key=<key>` optional

CLI examples:

```bash
ghodex +control todo-complete \
  --todo-id=01234567-89AB-CDEF-0123-456789ABCDEF \
  --completed=true
```

```bash
ghodex +control todo-complete \
  --todo-id=01234567-89AB-CDEF-0123-456789ABCDEF \
  --completed=false
```

### `todo-assign`

Assigns a todo item to a workspace tab, or clears the assignment.

Flags:

- `--todo-id=<uuid>` required
- `--workspace-id=<uuid>` optional
- `--date=YYYY-MM-DD` optional, defaults to today
- `--idempotency-key=<key>` optional

Rules:

- Omit `--workspace-id` to clear assignment.
- Carry-forward pointers resolve back to the source item automatically.

Assign example:

```bash
ghodex +control todo-assign \
  --todo-id=01234567-89AB-CDEF-0123-456789ABCDEF \
  --workspace-id=89ABCDEF-0123-4567-89AB-CDEF01234567
```

Clear assignment example:

```bash
ghodex +control todo-assign --todo-id=01234567-89AB-CDEF-0123-456789ABCDEF
```

### `todo-sync-stale`

Brings unfinished historical tasks into the target day as carry-forward pointers instead of cloning them as new tasks.

Flags:

- `--date=YYYY-MM-DD` optional, defaults to today
- `--idempotency-key=<key>` optional

CLI example:

```bash
ghodex +control todo-sync-stale --date=2026-03-23
```

Returns:

- mutation envelope with `operation = "todo-sync-stale"`
- `synced_count`
- refreshed target-day `snapshot`

## Snapshot Result Schema

`todo-snapshot` returns this object directly as `result`, and mutations return the same object under `result.snapshot`.

Fields:

- `date`: normalized day string, `YYYY-MM-DD`
- `include_completed`: whether completed rows were included in `items`
- `updated_at`: ISO 8601 timestamp for the day document
- `completion_rate`: `0...1`
- `total_count`: total items in the day document
- `completed_count`: completed items in the day document
- `remaining_count`: non-completed items in the day document
- `returned_count`: number of rows actually returned in `items`
- `items`: ordered todo rows

Todo item fields:

- `todo_id`: row ID to use in future todo mutations
- `source_day`: original day for carry-forward pointers, otherwise `null`
- `source_item_id`: original source item UUID for carry-forward pointers, otherwise `null`
- `title`
- `notes`
- `assigned_workspace_id`
- `is_completed`
- `completed_at`
- `created_at`
- `updated_at`
- `sort_order`
- `is_carry_forward_pointer`

Example snapshot result:

```json
{
  "date": "2026-03-23",
  "include_completed": true,
  "updated_at": "2026-03-23T08:15:30.123Z",
  "completion_rate": 0.5,
  "total_count": 4,
  "completed_count": 2,
  "remaining_count": 2,
  "returned_count": 4,
  "items": [
    {
      "todo_id": "01234567-89AB-CDEF-0123-456789ABCDEF",
      "source_day": null,
      "source_item_id": null,
      "title": "Call design review",
      "notes": "Bring timeline mock",
      "assigned_workspace_id": "89ABCDEF-0123-4567-89AB-CDEF01234567",
      "is_completed": false,
      "completed_at": null,
      "created_at": "2026-03-23T08:15:30.123Z",
      "updated_at": "2026-03-23T08:15:30.123Z",
      "sort_order": 3,
      "is_carry_forward_pointer": false
    }
  ]
}
```

## Mutation Result Schema

Todo mutations return:

```json
{
  "request_id": "req_add_001",
  "status": "ok",
  "result": {
    "operation": "todo-add",
    "date": "2026-03-23",
    "mutated_todo_id": "01234567-89AB-CDEF-0123-456789ABCDEF",
    "synced_count": null,
    "snapshot": {
      "...": "see snapshot schema above"
    }
  }
}
```

Fields:

- `operation`: one of `todo-add`, `todo-update`, `todo-complete`, `todo-assign`, `todo-sync-stale`
- `date`: target day after normalization
- `mutated_todo_id`: present for single-row mutations, `null` for sync
- `synced_count`: present for stale sync, otherwise `null`
- `snapshot`: post-mutation day snapshot

## Error Handling

Validation failures return `status: "error"` with machine-readable `error_code`.

Common error codes:

- `invalid_argument`
- `operation_failed`
- `app_unavailable`
- `idempotency_conflict`

Typical failure cases:

- malformed UUID in `todo_id` or `workspace_id`
- invalid `date`
- `todo-add` without a non-empty title
- `todo-update` without `title` or `notes`
- `todo-complete` without `completed=true|false`
- row not found in the target day or through pointer resolution

Example error:

```json
{
  "request_id": "req_complete_001",
  "status": "error",
  "error_code": "invalid_argument",
  "error_message": "todo-complete requires completed=true|false"
}
```

## Typical Automation Flows

### Add a task and capture its ID

1. Call `todo-add`
2. Read `result.mutated_todo_id`
3. Persist that ID for later update or completion

### Assign a task to the current workspace tab

1. Call base control-harness `snapshot`
2. Pick a target `tab_id`
3. Pass that UUID to `todo-assign --workspace-id=<tab_id>`

### Sync stale tasks into today, then inspect the result

1. Call `todo-sync-stale`
2. Read `result.synced_count`
3. Inspect `result.snapshot.items`
4. Watch for `is_carry_forward_pointer = true`

## Coverage and Non-Goals

The current API covers the todo operations already supported by the app:

- list day snapshot
- add item
- update title/notes
- toggle completion
- assign or clear workspace assignment
- sync stale unfinished tasks into today as pointers

Delete and reorder are intentionally not documented here because the current app store does not expose public control-harness operations for them yet. External programs should not mutate todo day files directly if they need those behaviors.
