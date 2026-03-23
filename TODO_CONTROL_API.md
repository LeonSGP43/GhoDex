# Todo Control API

This document describes the native Todo control surface exposed by the running GhoDex app through the control harness and the `ghodex +control` CLI.

## Transport

- Socket: the app listens on the same native control harness Unix socket used by the existing tab and terminal commands.
- CLI: use `ghodex +control <subcommand> ...` to send requests without hand-rolling socket JSON.
- Raw request shape: JSON request objects use snake_case keys such as `request_id`, `command`, `todo_id`, and `workspace_id`.

## Supported Todo Commands

### `todo-snapshot`

Returns the todo list snapshot for a day.

- Flags:
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
  "command": "todo-snapshot",
  "date": "2026-03-23",
  "include_completed": false
}
```

### `todo-add`

Creates a new todo item for a day.

- Flags:
  - `--title=<text>` required
  - `--notes=<text>` optional
  - `--date=YYYY-MM-DD` optional, defaults to today

CLI example:

```bash
ghodex +control todo-add --title="Call design review" --notes="Bring timeline mock" --date=2026-03-23
```

### `todo-update`

Updates the title and/or notes of an existing visible todo row.

- Flags:
  - `--todo-id=<uuid>` required
  - `--title=<text>` optional
  - `--notes=<text>` optional
  - `--date=YYYY-MM-DD` optional, defaults to today

Notes:

- At least one of `--title` or `--notes` must be provided.
- When the target row is a carry-forward pointer, the mutation is applied back to the source item.

CLI example:

```bash
ghodex +control todo-update --todo-id=01234567-89AB-CDEF-0123-456789ABCDEF --notes="Updated after QA pass"
```

### `todo-complete`

Marks a todo complete or incomplete.

- Flags:
  - `--todo-id=<uuid>` required
  - `--completed=true|false` required
  - `--date=YYYY-MM-DD` optional, defaults to today

CLI example:

```bash
ghodex +control todo-complete --todo-id=01234567-89AB-CDEF-0123-456789ABCDEF --completed=true
```

### `todo-assign`

Assigns a todo item to a workspace tab, or clears the assignment.

- Flags:
  - `--todo-id=<uuid>` required
  - `--workspace-id=<uuid>` optional
  - `--date=YYYY-MM-DD` optional, defaults to today

Notes:

- Omit `--workspace-id` to clear assignment.
- Carry-forward pointers resolve back to the source item automatically.

CLI example:

```bash
ghodex +control todo-assign --todo-id=01234567-89AB-CDEF-0123-456789ABCDEF --workspace-id=89ABCDEF-0123-4567-89AB-CDEF01234567
```

Clear assignment:

```bash
ghodex +control todo-assign --todo-id=01234567-89AB-CDEF-0123-456789ABCDEF
```

### `todo-sync-stale`

Brings unfinished historical tasks into the target day as carry-forward pointers instead of cloning them as new tasks.

- Flags:
  - `--date=YYYY-MM-DD` optional, defaults to today

CLI example:

```bash
ghodex +control todo-sync-stale --date=2026-03-23
```

## Response Shape

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
          "assigned_workspace_id": null,
          "is_completed": false,
          "completed_at": null,
          "created_at": "2026-03-23T08:15:30.123Z",
          "updated_at": "2026-03-23T08:15:30.123Z",
          "sort_order": 3,
          "is_carry_forward_pointer": false
        }
      ]
    }
  }
}
```

Snapshot queries return the `snapshot` object directly as `result`.

## Error Handling

- Validation failures return `status: "error"` with machine-readable `error_code`.
- Common cases:
  - `invalid_argument`
  - `operation_failed`
  - `app_unavailable`

## Coverage

The current API covers the todo operations already supported by the app:

- list day snapshot
- add item
- update title/notes
- toggle completion
- assign or clear workspace assignment
- sync stale unfinished tasks into today as pointers

Delete and reorder are not documented here because the current app store does not expose public control-harness operations for them yet.
