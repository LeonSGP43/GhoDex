# GhoDex Workspace Map Canvas Development Plan

## 1) Target State

- Introduce a new top-level tab mode: `Workspace Map`.
- Render all top-level tabs (terminal + browser) as independent groups on one infinite canvas.
- Preserve existing runtime ownership in controllers/models; map is projection and safe control surface only.
- Keep current mental model intact: top-level tabs + in-group pane tabs, with clear hierarchy visibility.

## 2) Hard Architecture Contract

### 2.1 One-Way Data and Mutation Rules

- Data flow: `Runtime -> RuntimeAdapter -> ProjectionService -> Immutable Snapshot/ViewModel -> Canvas Renderer`.
- Mutation flow: `Canvas Renderer/UI -> CommandGateway -> Runtime`.
- Forbidden: renderer directly importing runtime mutation APIs.
- Forbidden: snapshot/layout storing runtime object references (`NSView`, controller instances, bridges).
- Forbidden (v1): split-tree structural edits from canvas (`editSplitTree` must stay blocked).

### 2.2 Layer Ownership and Extension Seams (Best-Practice Baseline)

| Layer | Primary Files | Owns | Allowed Dependencies | Forbidden Dependencies |
| --- | --- | --- | --- | --- |
| Runtime Adapter | `WorkspaceMapRuntimeAdapter.swift` | Runtime read extraction into DTO/value input | Runtime controllers + Projection input types | SwiftUI view concerns, mutation gateway |
| Projection | `WorkspaceMapProjectionService.swift`, `WorkspaceMapContracts.swift` | Deterministic immutable graph snapshot | Adapter input/value contracts | Runtime mutation paths, UI rendering state |
| Command Gateway | `WorkspaceMapCommandHandler.swift` | Allowlist validation + runtime command routing | Runtime mutation APIs, contract request/result types | Renderer state internals, projection internals |
| Canvas/ViewModel | `WorkspaceMapController.swift` | Pan/zoom/group state presentation and user actions | Snapshot/view model + command gateway + layout store | Direct runtime mutation |
| Layout Persistence | `WorkspaceMapLayoutStore.swift` | Map-only position/viewport/zoom/collapsed schema | File persistence + layout contracts | Runtime restore payload schema |
| Performance | `WorkspaceMapPerformance.swift` | Latency/publish/action metrics and budgets | Controller hooks + debug logging | Runtime mutation and business logic |
| Test Boundary | `macos/Tests/WorkspaceMap/*` | Determinism/boundary/command/perf regression coverage | Test fixtures and public APIs | Private runtime internals via reflection |

### 2.3 Boundary Enforcement (Release-Blocking)

- [x] Runtime reference leakage negative test exists (`WorkspaceMapProjectionBoundaryTests`).
- [x] Gateway allowlist and blocked-command policy tests exist (`WorkspaceMapContractsTests`, `WorkspaceMapCommandGatewayTests`).
- [x] Snapshot semantic equality gate exists (`WorkspaceMapContractsTests`) to avoid timestamp-only churn.
- [x] Add static dependency guard script (import boundary check for Workspace Map module).
- [x] Add CI fail-closed step for boundary guard script.

## 3) Performance and Scalability SLOs (Release-Blocking)

### 3.1 Reproducible Workloads

- `Large-A`: 20 top-level groups (12 terminal + 8 browser), 120 panes, 360 pane-tabs.
- `Large-B`: burst refresh mode with 200 focus/switch events in 10 seconds.
- `Large-C`: command burst with 10 concurrent rename/focus/close operations in 5 seconds.

### 3.2 Numeric Thresholds (Must Be Met Per Workload)

| Metric | Large-A | Large-B | Large-C |
| --- | --- | --- | --- |
| Snapshot build p95 | <= 25 ms | <= 20 ms | <= 20 ms |
| Snapshot build p99 | <= 40 ms | <= 35 ms | <= 35 ms |
| Publish cadence | <= 12 updates/sec | <= 20 updates/sec | <= 15 updates/sec |
| Main-thread spike markers (>32 ms) | <= 2 per run | <= 5 per run | <= 3 per run |
| Command action p95 | <= 50 ms | <= 55 ms | <= 45 ms |
| Command failure rate (allowlisted commands) | 0% | 0% | 0% |

### 3.3 Fail-Closed Rules

- Missing metric artifact for any required workload => automatic gate failure.
- Any threshold breach without mitigation task + owner + due milestone => automatic gate failure.
- Metrics must be collected from deterministic test/benchmark entrypoints, not manual observation only.

## 4) Detailed Work Breakdown (Task Checklist)

### WS0. Contracts and ID Model

- [x] WS0-T1 Define schema version contract (`WorkspaceMapGraphSchemaVersion`).
- [x] WS0-T2 Define stable entity ID model (`WorkspaceMapEntityID`) for terminal/browser/split/pane/pane-tab.
- [x] WS0-T3 Define v1 command enums + request/result contracts.
- [x] WS0-T4 Add semantic snapshot equality that ignores `generatedAt`.
- Acceptance:
  - All contracts are value types (`Codable`, `Hashable`, `Sendable` where applicable).
  - ID parse/build paths are deterministic and test-covered.

### WS1. Entry Integration (Mode Toggle Only)

- [x] WS1-T1 Expose `Workspace Map` only as a mode switch entrypoint (menu/shortcut/settings), not as a new-tab type.
- [x] WS1-T2 Ensure top-level and pane-child New Tab Picker flows never surface a workspace-map creation entry.
- [x] WS1-T3 Keep picker filtering/search free from workspace-map synthetic entries.
- [x] WS1-T4 Wire toggle behavior through `AppDelegate` open/focus/close mode semantics.
- Acceptance:
  - `NewTabPickerWorkspaceMapTests` and `AppDelegateWorkspaceMapModeTests` pass.

### WS2. Runtime Adapter and Projection Foundation

- [x] WS2-T1 Introduce runtime adapter DTO path (`WorkspaceMapRuntimeAdapter`).
- [x] WS2-T2 Keep projection pure (side-effect free on immutable input).
- [x] WS2-T3 Project terminal + browser groups into a single snapshot.
- [x] WS2-T4 Add deterministic ordering by kind and stable ID.
- Acceptance:
  - Same input + same clock => byte-identical snapshot JSON.
  - Snapshot generation has no runtime mutation side effects.

### WS3. Terminal Tree Projection (Split/Pane/Pane-Tab)

- [x] WS3-T1 Recursively project split tree with direction/ratio metadata.
- [x] WS3-T2 Emit parent-child linkage for split/pane/pane-tab nodes.
- [x] WS3-T3 Include root node pointer and focused-state markers.
- [x] WS3-T4 Keep split path IDs deterministic across stable topology.
- Acceptance:
  - Fixture tests validate hierarchy shape, counts, and link consistency.

### WS4. Command Gateway (Policy-First Runtime Control)

- [x] WS4-T1 Implement explicit allowlist enforcement in command handler.
- [x] WS4-T2 Support v1 commands: focus/rename/close/jump.
- [x] WS4-T3 Hard-block split edit command (`editSplitTree`).
- [x] WS4-T4 Route all runtime operations through injected gateway dependencies.
- Acceptance:
  - Blocked commands return deterministic policy rejection.
  - Gateway tests verify routing and target validation behavior.

### WS5. Canvas Rendering Mode (Infinite Canvas v1)

- [x] WS5-T1 Replace list mode with pan/zoom canvas renderer.
- [x] WS5-T2 Render top-level groups as independent movable units.
- [x] WS5-T3 Add expand/collapse controls and depth minimap view.
- [x] WS5-T4 Bind focus/rename/close actions to command gateway.
- Acceptance:
  - Map opens as top-level tab and displays logical grouping on one canvas.
  - No view-layer direct runtime mutation path exists.

### WS6. Layout Persistence (Map-Only Schema)

- [x] WS6-T1 Persist group coordinates, viewport offset, zoom level, collapsed state.
- [x] WS6-T2 Keep layout schema version independent from runtime restore schema.
- [x] WS6-T3 Implement resilient restore for missing/deleted IDs.
- [x] WS6-T4 Keep runtime state immutable during layout restore.
- Acceptance:
  - Restart restores map layout and ignores missing IDs without crash/corruption.

### WS7. Instrumentation and Budget Hooks

- [x] WS7-T1 Add snapshot latency metrics (p50/p95/p99 aggregates).
- [x] WS7-T2 Add publish cadence and command action latency metrics.
- [x] WS7-T3 Add coalescing hooks to protect UI from event storms.
- [x] WS7-T4 Add benchmark/perf regression entrypoints for Large workloads.
- [x] WS7-T5 Wire per-workload numeric threshold evaluation output (`PASS/FAIL`) into artifacts.
- Acceptance:
  - Metrics are logged and machine-readable for gate evaluation.
  - Threshold evaluation is explicit per workload and fail-closed.

### WS8. Test Matrix and Regression Harness

- [x] WS8-T1 Contracts/policy tests (`WorkspaceMapContractsTests`).
- [x] WS8-T2 Picker integration tests (`NewTabPickerWorkspaceMapTests`).
- [x] WS8-T3 Projection fixture determinism tests (`WorkspaceMapProjectionFixtureTests`).
- [x] WS8-T4 Projection boundary tests (`WorkspaceMapProjectionBoundaryTests`).
- [x] WS8-T5 Command gateway tests (`WorkspaceMapCommandGatewayTests`).
- [x] WS8-T6 ViewModel determinism/coalescing tests (`WorkspaceMapViewModelDeterminismTests`).
- [x] WS8-T7 Performance regression tests (`WorkspaceMapPerformanceRegressionTests`).
- Acceptance:
  - All seven test classes pass in `build-for-testing + xctest` chain.
  - Boundary and determinism tests fail closed on policy regressions.

### WS9. Documentation and Operator Readiness

- [x] WS9-T1 Document stable ID semantics and split identity lifecycle.
- [x] WS9-T2 Document v1 allowlist, blocked commands, and rationale.
- [x] WS9-T3 Document runtime-vs-layout schema separation and migration policy.
- [x] WS9-T4 Add operator runbook for latency/publish cadence troubleshooting.
- Acceptance:
  - Docs match actual implementation and include deferred v2 scope explicitly.

### WS10. Static Boundary Automation (Best-Practice Completion)

- [x] WS10-T1 Add workspace-map boundary check script (import/path rules).
- [x] WS10-T2 Add CI hook to run boundary script + Workspace Map test matrix.
- [x] WS10-T3 Add pull-request checklist item requiring boundary evidence artifacts.
- Acceptance:
  - Boundary violations fail CI before merge.
  - Dependency direction drift is blocked automatically.

## 5) Opus Acceptance Gates (Required)

Opus must produce `PASS/FAIL` for each gate with file-level evidence:

- Gate A: Architecture correctness.
  - One-way data and mutation rules are enforced.
  - Snapshot/layout are runtime-reference free.
  - Layer ownership boundaries are respected.
- Gate B: Performance readiness.
  - Metrics exist and map to numeric workload thresholds.
  - Coalescing/publish behavior is verifiable.
- Gate C: Extensibility and maintainability.
  - Schema/version evolution path is explicit.
  - Command policy supports safe v1 + clean v2 expansion.
  - Boundary automation plan is concrete and enforceable.
- Gate D: Requirement fit.
  - Top-level tabs are visualized as canvas groups.
  - Existing top-level + pane-tab behavior remains consistent.

Pass criteria:

- Hard release gate requires WS5/WS6/WS7/WS8 = complete with evidence.
- No unresolved high-severity architecture/safety findings.
- Any medium/low gaps must map to explicit WS task IDs with owners and acceptance checks.

## 6) Evidence Artifact Schema (Mandatory Per WS Item)

Each completed task must include:

- `ws_id`: workstream ID (`WS0`..`WS10`).
- `task_id`: task ID (`WSx-Ty`).
- `timestamp`: ISO-8601 timestamp.
- `command`: exact command or test invocation.
- `result`: `PASS` or `FAIL`.
- `metrics`: key-value metrics (include thresholds and measured values when relevant).
- `artifact`: log/test/xcresult/file path.
- `verdict`: brief conclusion and next action if failed.

## 7) Current Verification Snapshot (2026-03-29)

- `xcodebuild build-for-testing` (macOS arm64, code-sign disabled): PASS.
- `xcodebuild build` (macOS arm64, code-sign disabled): PASS.
- `bash scripts/ci/check_workspace_map_boundaries.sh`: PASS.
- `bash scripts/ci/run_workspace_map_test_matrix.sh`: PASS.
- Workspace Map class tests (direct `xctest`): PASS.
  - `NewTabPickerWorkspaceMapTests`
  - `WorkspaceMapContractsTests`
  - `WorkspaceMapProjectionFixtureTests`
  - `WorkspaceMapProjectionBoundaryTests`
  - `WorkspaceMapCommandGatewayTests`
  - `WorkspaceMapViewModelDeterminismTests`
  - `WorkspaceMapPerformanceRegressionTests`
  - `WorkspaceMapPerformancePolicyTests`
- Runtime workload artifact integration:
  - `WorkspaceMapViewModelDeterminismTests.testRuntimePathProducesPassingPerWorkloadArtifacts`: PASS.
- Known environment limitation:
  - `xcodebuild test -only-testing:GhosttyTests/NewTabPickerWorkspaceMapTests` still hangs in host bootstrapping path in this environment; direct `xctest` remains the stable verification path.

## 8) Remaining Release Blockers

- None. WS0..WS10 are complete and the final Opus strict acceptance rerun passed.

## 9) Opus Strict Acceptance History (2026-03-29)

- Verdict: `FAIL` (release gate not met yet).
- Confirmed implemented-now:
  - top-level terminal/browser groups rendered in one canvas mode;
  - one-way `runtime -> snapshot -> canvas` flow and command allowlist path are in place;
  - current Workspace Map test matrix passes via `build-for-testing + xctest`.
- Mandatory blockers from Opus:
  - `WS7-T5` must emit per-workload threshold `PASS/FAIL` artifacts and align code-side budgets with plan thresholds.
  - `WS9-T1..T4` must complete docs/runbook delivery.
  - `WS10-T1..T3` must add static boundary guard and CI fail-closed enforcement.
  - Product wording mismatch must be resolved: either implement truly unbounded canvas or explicitly redefine requirement as large bounded canvas.
- Engineering warning from Opus:
  - main-actor heavy projection path may hitch at larger scale; split runtime capture (main) vs projection compute (background) in next increment.

## 10) Closure Added After Opus Fail

- Runtime workload tagging is now wired in `WorkspaceMapViewModel` classification path.
- Canvas rendering no longer depends on a fixed backing frame; viewport operates over logical coordinates.
- Docs added in `docs/workspace-map-v1.md`.
- CI automation added:
  - `scripts/ci/check_workspace_map_boundaries.sh`
  - `scripts/ci/run_workspace_map_test_matrix.sh`
  - `.github/workflows/test.yml`
  - `.github/PULL_REQUEST_TEMPLATE.md`

## 11) Final Opus Strict Acceptance Result (2026-03-29)

- Verdict: `PASS`.
- Gate A Architecture correctness: `PASS`.
- Gate B Performance readiness: `PASS`.
- Gate C Extensibility and maintainability: `PASS`.
- Gate D Requirement fit: `PASS`.
- No blocking findings remain.
  - `.github/workflows/test.yml`
  - `.github/PULL_REQUEST_TEMPLATE.md`

## 12) Post-PASS Hardening Follow-up (2026-03-30)

- [x] WS5-H1 Replace live-canvas runtime ownership mutation path with non-owning mirrored lease provider.
  - `WorkspaceMapRuntimeLiveCanvasContentProvider` now resolves source views read-only and returns mirror surfaces.
  - No `sourceWindow.contentView = ...` ownership reassignment remains in Workspace Map provider path.
- [x] WS8-H1 Add lease safety and policy tests for live content provider.
  - Added `WorkspaceMapLiveCanvasContentProviderTests` covering:
    - acquire/release without source window mutation,
    - release idempotency,
    - browser-group hard reject before resolver use,
    - terminal-unavailable path.
- [x] WS8-H2 Extend Workspace Map matrix to include newly added canvas interaction/provider tests.
  - `WorkspaceMapCanvasInputPolicyTests`
  - `WorkspaceMapLiveCanvasViewVisibilityTests`
  - `WorkspaceMapLiveCanvasContentProviderTests`
- [x] WS11-H1 Re-run strict Opus acceptance for Req4/Req6 closure and archive PASS/FAIL evidence.
  - `opus_workspace_map_acceptance` verdict: `PASS` (Req4=`PASS`, Req6=`PASS`), reviewed on 2026-03-30.
