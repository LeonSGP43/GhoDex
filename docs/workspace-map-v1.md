# Workspace Map v1

## Purpose

Workspace Map is a top-level tab mode that projects all top-level terminal and browser groups onto one canvas. The canvas is a read-mostly control surface: runtime controllers remain the source of truth, and v1 keeps two explicit control planes:

- command-gateway control (explicit v1 command allowlist),
- terminal live-input passthrough inside leased mirror views (non-owning input forwarding only).

In v1, "infinite canvas" means the viewport pans and zooms over an unbounded logical coordinate space. Group cards are positioned by persisted logical coordinates instead of by a fixed backing frame.

Entry policy (required):

- Workspace Map is a mode switch, not a new-tab content type.
- Entry points are menu/shortcut/settings toggle only.
- New Tab Picker top-level and pane-child flows must not expose a Workspace Map creation entry.

Rendering policy (v1 safety boundary):

- Terminal groups are presented as non-owning mirrored surfaces in canvas mode.
- Browser groups remain non-destructive summary/live-control nodes until a dedicated browser host abstraction is introduced.
- Rendering paths must not mutate runtime `NSWindow`/`NSView` ownership.
- Terminal mirror passthrough may forward keyboard/mouse input to runtime responders, but must not transfer view/window ownership.

Deferred v2 scope:

- split-tree structural editing
- arbitrary node creation/deletion from the canvas
- cross-group drag/drop mutation
- background projection off the main actor

## Stable Identity Semantics

The identity contract is defined in [WorkspaceMapContracts.swift](/Users/leongong/Desktop/LeonProjects/GhoDex/macos/Sources/Features/Workspace%20Map/WorkspaceMapContracts.swift).

- `terminal-group:<uuid>` identifies one top-level terminal workspace.
- `browser-group:<uuid>` or `browser-group:<external-id>` identifies one top-level browser workspace.
- `pane:<uuid>` identifies a terminal pane.
- `pane-tab:<uuid>` identifies a terminal tab inside a pane.
- `split:<group-id>:<path>` identifies a split node by deterministic branch path.

Split identity lifecycle:

- Split IDs are not stored by the runtime.
- Projection rebuilds the split ID from the owning top-level group ID plus the recursive branch path (`root`, `l`, `r`, `l.r`, etc.).
- If split topology is unchanged, the split ID is stable across refreshes.
- If topology changes, affected split IDs are allowed to change because the path changed.

Operator implication:

- Persisted layout is keyed only by top-level group IDs, not by split IDs.
- Runtime restore and Workspace Map layout restore are intentionally separate concerns.

## Command Policy

The v1 command contract is implemented in [WorkspaceMapCommandHandler.swift](/Users/leongong/Desktop/LeonProjects/GhoDex/macos/Sources/Features/Workspace%20Map/WorkspaceMapCommandHandler.swift) and enforced by [WorkspaceMapContractsTests.swift](/Users/leongong/Desktop/LeonProjects/GhoDex/macos/Tests/WorkspaceMap/WorkspaceMapContractsTests.swift).

Scope note:

- The command allowlist governs explicit canvas command actions routed through the command gateway.
- Terminal live-input passthrough in leased mirror views is a separate rendering/input path and is intentionally outside the command enum allowlist.

Allowed in v1:

- `focusTopLevelGroup`
- `renameTopLevelGroup`
- `closeTopLevelGroup`
- `jumpToTerminalPaneTab`

Blocked in v1:

- `editSplitTree`

Rationale:

- The map is a safe projection surface first.
- Allowlisted commands map to existing runtime actions with deterministic targets.
- Structural edits would require transactional split-tree ownership, conflict handling, and stronger undo/redo guarantees. That is deferred to v2.

## Runtime and Layout Schema Separation

Workspace Map uses two independent schemas:

- Graph snapshot schema:
  - versioned by `WorkspaceMapGraphSchemaVersion`
  - contains immutable runtime projection data
  - regenerated from runtime state on refresh
- Layout schema:
  - versioned by `WorkspaceMapLayoutSchemaVersion`
  - contains only viewport offset, zoom, group positions, and collapsed state
  - persisted by [WorkspaceMapLayoutStore.swift](/Users/leongong/Desktop/LeonProjects/GhoDex/macos/Sources/Features/Workspace%20Map/WorkspaceMapLayoutStore.swift)

Migration policy:

- Graph schema changes must remain additive or require an explicit version bump.
- Layout schema changes must not assume runtime objects or controller references.
- Missing layout IDs are ignored during restore.
- Deleted runtime groups are dropped from layout on the next reconcile pass.

Forbidden data in either schema:

- `NSView`
- `NSWindow`
- controller instances
- bridge pointers
- any non-serializable runtime ownership reference

## Performance and Workload Gates

The performance contract lives in [WorkspaceMapPerformance.swift](/Users/leongong/Desktop/LeonProjects/GhoDex/macos/Sources/Features/Workspace%20Map/WorkspaceMapPerformance.swift) and [plan.md](/Users/leongong/Desktop/LeonProjects/GhoDex/plan.md).

Workloads:

- `Large-A`: 20 top-level groups, 120 panes, 360 pane-tabs
- `Large-B`: burst refresh mode
- `Large-C`: command burst mode

Rules:

- Missing artifact data for any workload is a hard failure.
- Each workload emits explicit `PASS` or `FAIL`.
- Thresholds are evaluated per workload, not from one shared aggregate.

The runtime path classifies workload samples from observed snapshot scale, refresh burst density, and command burst density in [WorkspaceMapController.swift](/Users/leongong/Desktop/LeonProjects/GhoDex/macos/Sources/Features/Workspace%20Map/WorkspaceMapController.swift).

## Operator Runbook

### Symptom: canvas feels laggy

1. Run the boundary and test harness:

```bash
bash scripts/ci/check_workspace_map_boundaries.sh
bash scripts/ci/run_workspace_map_test_matrix.sh
```

2. Inspect the Workspace Map status line in-app:

- snapshot `p95`
- snapshot `p99`
- command `p95`
- publish cadence
- spike count
- overall gate

3. If `Large-A` fails:

- suspect projection cost or node explosion
- inspect [WorkspaceMapProjectionService.swift](/Users/leongong/Desktop/LeonProjects/GhoDex/macos/Sources/Features/Workspace%20Map/WorkspaceMapProjectionService.swift) first

4. If `Large-B` fails:

- suspect refresh storm/coalescing regression
- inspect `scheduleRefresh()` and event producers in [WorkspaceMapController.swift](/Users/leongong/Desktop/LeonProjects/GhoDex/macos/Sources/Features/Workspace%20Map/WorkspaceMapController.swift)

5. If `Large-C` fails:

- suspect command routing latency or repeated synchronous refresh cost
- inspect command path in [WorkspaceMapCommandHandler.swift](/Users/leongong/Desktop/LeonProjects/GhoDex/macos/Sources/Features/Workspace%20Map/WorkspaceMapCommandHandler.swift) and [WorkspaceMapController.swift](/Users/leongong/Desktop/LeonProjects/GhoDex/macos/Sources/Features/Workspace%20Map/WorkspaceMapController.swift)

### Symptom: workload status shows `missing_artifact_data`

- The runtime path is not producing enough samples for one or more workloads.
- Confirm the benchmark/test entrypoint exercised that workload.
- Re-run `bash scripts/ci/run_workspace_map_test_matrix.sh`.
- If it still reproduces, inspect the workload classifier and recorder wiring in [WorkspaceMapController.swift](/Users/leongong/Desktop/LeonProjects/GhoDex/macos/Sources/Features/Workspace%20Map/WorkspaceMapController.swift) and [WorkspaceMapPerformance.swift](/Users/leongong/Desktop/LeonProjects/GhoDex/macos/Sources/Features/Workspace%20Map/WorkspaceMapPerformance.swift).

### Symptom: boundary check fails

- Read the exact import/token violation emitted by `check_workspace_map_boundaries.sh`.
- Move runtime reads back into `WorkspaceMapRuntimeAdapter`.
- Move runtime mutations back into `WorkspaceMapCommandHandler`.
- Keep contracts, projection, layout, and performance layers free of AppKit view/controller ownership.
