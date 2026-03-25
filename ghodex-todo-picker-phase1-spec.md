# GhoDex Todo + Picker Spec

## Summary

- Goal: add a manual-first todo workflow to GhoDex, expose it quickly from anywhere in-app, surface per-tab task progress, and improve New Tab picker information density.
- Principle: keep the Settings Panel as the durable configuration/editor shell, but use an in-window side panel for fast task review/update.
- Priority: deterministic local UX first, AI later only as a draft helper.

## Product Goals

1. Let the user inspect and update today's todo list quickly inside GhoDex.
2. Keep todo data human-visible and editable on disk.
3. Let the user assign tasks to a specific top-level tab object and see that tab's current progress without leaving the tab.
4. Avoid AI-driven surprise writes for personal task state.
5. Improve picker visibility so the user can see significantly more launch targets at once.

## Non-Goals

- No AI auto-complete or auto-reprioritization.
- No system-global hotkey capture outside the app.
- No recurring tasks, priorities, labels, or cross-device sync.
- No changes to picker search rules, section order, or launch semantics.

## UX

### Todo Tab

- Add `Todo` as a new Settings Panel tab.
- Show:
  - enable toggle,
  - todo workspace root path,
  - derived selected day file path,
  - side-panel left/right placement,
  - in-tab quick-look visibility and placement,
  - initialization button,
  - selected date switcher with quick `Today`,
  - today completion summary,
  - timeline list for the selected day,
  - manual add / edit / complete / reset controls.
- Keep state changes explicit and local.

### Quick Access

- Add an app-wide menu action and in-app shortcut that toggles an in-window Todo side panel for the current terminal tab.
- Keep the Settings Panel `Todo` tab available for full settings management and bootstrap actions.
- When launched from a terminal tab, the side panel should focus that tab as the current workspace target.

### Workspace Assignment

- Each todo item may be assigned to one live top-level workspace/tab.
- The Settings Panel shows the focused workspace summary when it was opened from a specific tab.
- Terminal tabs show:
  - a titlebar progress summary when they have assigned tasks,
  - an in-tab quick-look card with today's assigned items,
  - direct complete/reset toggles for those assigned items,
  - a path back into the in-window Todo panel or full `Todo` settings page.

### Picker

- Keep the current one-window flow, search field, keyboard shortcuts, and opening logic.
- Increase window size and minimum size.
- Reduce row padding and card bulk.
- Keep sectioning, selection order, and `1...9` shortcuts stable.

## Data Model

### Config-backed Todo Settings

- `enabled: Bool`
- `workspaceRootPath: String`
- `showCompletedItems: Bool`
- `selectedDateAnchor: String`
- `sidebarEdge: leading | trailing`
- `workspaceOverlayVisible: Bool`
- `workspaceOverlayCorner: top-leading | top-trailing | bottom-leading | bottom-trailing`

### Daily Todo File

- File path: `<workspaceRootPath>/days/YYYY-MM-DD.json`
- JSON structure:
  - `date`
  - `updatedAt`
  - `items`
- Each item stores:
  - `id`
  - `title`
  - `notes`
  - `assignedWorkspaceID`
  - `isCompleted`
  - `completedAt`
  - `createdAt`
  - `sortOrder`

## Workspace Layout

- Root: `/Users/leongong/Desktop/LeonProjects/gho_workspace/gho_todolist_workspace`
- Required files:
  - `creator.md`
  - `README.md`
  - `days/`

## AI Boundary

- Phase 1 ships with no AI todo mutation path.
- Future optional AI support may only:
  - parse free text into draft items,
  - suggest date placement,
  - propose structured candidate edits.
- Future AI support may not:
  - directly modify completion state,
  - delete tasks without confirmation,
  - rewrite task history silently,
  - auto-save parsed output without review.

## Implementation Notes

- Extend `AITerminalManagerConfiguration` with a new todo settings block and presentation preferences.
- Add dedicated todo store logic to `AITerminalManagerStore`.
- Use the stable top-level tab/workspace UUID as the assignment key.
- Keep todo file IO deterministic and synchronous-at-boundary, with async only where UI responsiveness needs it.
- Reuse the existing Settings Panel tab switching model for durable settings and use an in-window side panel for rapid task work.
- Do not overload heartbeat queue or learning logs for todo state.

## Validation

- Config reload must repopulate the Todo tab correctly.
- Config reload must repopulate the side-panel side and quick-look placement/visibility correctly.
- Creating the todo workspace must be idempotent.
- Empty selected day should render a stable empty state.
- Completion rate must match `completed / total` for today.
- Workspace summaries must match the tasks assigned to that workspace id for the selected day.
- Clearing an assignment must remove the task from that workspace summary on reload.
- Picker keyboard behavior must remain unchanged after the UI polish.
