# GhoDex Todo + Picker Doc

## Decision Trail

- Todo belongs in the Settings Panel because it is workflow state, not a terminal surface.
- Todo must not be built on top of the learning command-execution path because learning currently optimizes for controlled command templates, not task-state correctness.
- Todo and Task Queue stay separate because one represents personal task tracking and the other represents scheduled terminal command execution.
- Fast todo access still belongs to the app shell, but the quick entry point should stay inside the current tab context, so `Cmd+Shift+M` now opens an in-window side panel and leaves the Settings Panel as the durable configuration/editor surface.
- Task assignment must attach to the stable top-level workspace/tab object, not to transient panes or focused surfaces inside a split tree.
- The tab quick-look card is useful for ambient awareness but should not cover content by default, so its placement and visibility are config-backed.
- Picker work is intentionally visual-only in phase 1 to reduce regression risk.

## File / State Ownership

- Main config owns todo settings and UI preferences.
- `gho_todolist_workspace` owns day-by-day task content.
- `AITerminalManagerStore` remains the app-facing coordinator, but todo models stay independent from learning models.
- Per-task `assignedWorkspaceID` links a todo item to a top-level tab/workspace object.
- Terminal UI surfaces may read and mutate assigned items, but they still route through the same store/file path as the Settings Panel.
- The in-window side panel and the Settings Panel share the same config-backed selected date and completed-item visibility settings.

## Default Paths

- Todo workspace root:
  - `/Users/leongong/Desktop/LeonProjects/gho_workspace/gho_todolist_workspace`
- Daily files:
  - `/Users/leongong/Desktop/LeonProjects/gho_workspace/gho_todolist_workspace/days/YYYY-MM-DD.json`

## Verification Checklist

- Todo settings save into config.
- Todo settings reload from config into the panel.
- Todo presentation settings reload from config into both the Settings Panel and the in-window side panel.
- Todo workspace scaffold creates its required files.
- Manual task mutations rewrite the selected day file predictably.
- Assigning a task to a workspace persists to the daily JSON file and reloads correctly.
- The app-wide todo action opens the in-window side panel instead of leaving the current tab.
- Workspace quick-look summaries match the assigned tasks for the active tab.
- Picker still supports:
  - search,
  - up/down selection,
  - `Enter` to open,
  - `Esc` to cancel,
  - numeric quick open.

## Deferred Work

- AI-assisted draft parsing behind explicit confirmation.
- Richer workspace/task grouping beyond single-tab assignment.
- System-global hotkey capture outside the app.
