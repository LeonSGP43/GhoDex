# GhoDex Todo + Picker Plan

## Target State

- Add a manual-first todo workflow to GhoDex with:
  - a dedicated `Todo` tab inside the existing Settings Panel,
  - config-backed settings plus date-based task files under `gho_todolist_workspace`,
  - today / other days navigation,
  - timeline-style presentation for the selected day,
  - completion rate for today,
  - explicit manual add / edit / complete / reset flows,
  - app-wide quick access to the todo workspace from any GhoDex screen,
  - per-workspace task assignment and a tab-local quick-look surface.
- Keep AI out of the default write path.
- Improve the New Tab picker visually without changing its search, ordering, keyboard traversal, or open behavior.

## Scope

### In Scope

- `Todo` settings + runtime state model.
- Config file round-trip for todo settings.
- Workspace scaffold for `gho_todolist_workspace`.
- Date-based todo file loading and saving.
- Settings Panel `Todo` tab UI.
- App-wide todo entry point that opens the Settings Panel directly to `Todo`.
- Per-workspace assignment state on todo items.
- Per-workspace quick-look status in terminal tabs and inside terminal content.
- Picker density and size improvements.
- Unit tests for config decoding, persistence, todo file IO, workspace assignment/progress, and picker behavior that should remain stable.
- Changelog entry and durable decision notes.

### Out of Scope

- AI-driven automatic todo updates.
- System-wide hotkey registration outside the app.
- Recurring tasks, priorities, tags, syncing, cloud storage.

## Deliverables

### Spec

- [`ghodex-todo-picker-phase1-spec.md`](./ghodex-todo-picker-phase1-spec.md)

### Implementation Doc

- [`ghodex-todo-picker-phase1-doc.md`](./ghodex-todo-picker-phase1-doc.md)

### Code

- macOS todo models, store logic, settings-panel tab, app-wide quick access, per-workspace quick look, picker UI updates, localization, config wiring, tests, changelog.

## Execution Sequence

1. Add the phase-1 spec and implementation doc.
2. Introduce todo data models, defaults, and config schema wiring.
3. Add store APIs for scaffolding, reading, updating, and persisting daily todo files.
4. Add the Settings Panel `Todo` tab and bind it two-way with config + file state.
5. Add app-wide quick access and per-workspace assignment/progress surfaces.
6. Tighten New Tab picker layout, sizing, and row density while preserving existing behavior.
7. Add targeted tests for the new todo path, workspace assignment path, and picker non-regression behavior.
8. Update `CHANGELOG.md` with feature entries and decision trail.
9. Run targeted verification.

## Spec Summary

- Todo is its own domain. It reuses the Settings Panel container but does not reuse the learning command-execution path.
- Main config stores todo settings and UI preferences.
- Task content lives in the user-visible workspace folder at `/Users/leongong/Desktop/LeonProjects/gho_workspace/gho_todolist_workspace`.
- Day files are human-readable JSON for deterministic machine round-trip and safe editing.
- Manual UI actions are the only default state mutation path.
- Todo items may be assigned to a stable top-level workspace/tab id.
- The app must expose a fast in-app todo entry point and a tab-local quick-look view for assigned tasks.
- AI, if added later, can only produce draft candidates that require explicit user confirmation.

## Test Plan

### Unit Tests

- Legacy config decoding gets default todo settings.
- Todo settings persist through managed config rendering and reload.
- Todo workspace scaffold creates the expected root files and default daily file path.
- Todo store loads an empty day deterministically.
- Completing, resetting, adding, editing, assigning, and clearing todo items update the selected day file and recompute completion rate/workspace summaries.
- Picker entry ordering and launch behavior remain unchanged after the UI refactor.

### Targeted Build / Test Commands

- `zig build -Demit-xcframework=true -Demit-macos-app=false`
- `xcodebuild test -parallel-testing-enabled NO -project macos/GhoDex.xcodeproj -scheme GhoDex -destination 'platform=macOS,arch=arm64' -skip-testing GhosttyUITests`

## Documentation Requirements

- Update `CHANGELOG.md` in the same change set.
- Keep a decision trail in the changelog and the phase-1 doc.
- Document file layout, config keys, and deferred AI boundaries in the implementation doc.

## Acceptance Criteria

- The Settings Panel shows a working `Todo` tab beside the existing tabs.
- Todo settings round-trip through config and refresh the panel correctly after reload.
- The todo workspace root can be scaffolded under the default `gho_workspace`.
- The selected day view supports manual add / edit / complete / reset.
- The user can open the todo workspace from anywhere in GhoDex through an app-wide shortcut/menu action.
- Todo items can be assigned to a specific top-level tab object and that assignment persists on disk.
- A terminal tab shows its assigned-task progress inside the tab UI and exposes a quick in-tab view for manual completion/reset.
- Today completion rate updates correctly.
- The New Tab picker shows materially more items per screen without behavior regressions.
- Targeted tests pass, or any unrun verification is explicitly called out.
