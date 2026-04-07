# PageList Viewport Normalization Fix

## Scope

This note documents the `PageList` viewport fix shipped in
`src/terminal/PageList.zig`.

The change is intentionally scoped to viewport normalization after layout
changes. It does not alter the integrity assertion itself.

## Problem

`PageList.verifyIntegrity()` requires a pinned viewport to have enough rows
available below the pin:

- `remaining_rows = self.total_rows - actual_offset`
- the invariant is `remaining_rows >= self.rows`

The failure mode was that some code paths changed `total_rows` or the active
boundary and left `self.viewport` as an illegal `.pin`. The next integrity
check then failed with `ViewportPinInsufficientRows`.

Observed weak spots before this fix:

- `resize()` had an inline `.pin -> .active` fixup, but the `!reflow` path
  returned early into `resizeWithoutReflow()`
- `resizeWithoutReflow()` only repaired one row-growth branch
- `grow()` prune logic updated cached row offsets, but did not consistently
  normalize the viewport itself
- row-removal paths still relied on older `fixupViewport()` behavior

## Fix Strategy

The fix centralizes viewport repair in one helper:

- `normalizeViewportAfterLayoutChange()`

Helper behavior:

1. Clear `self.viewport_pin_row_offset`
2. Preserve existing viewport semantics:
   - prefer `.active` when `.active` and `.top` overlap
   - only fall back to `.top` when the pin truly maps to the top
3. For `.pin`, compute the real viewport offset if needed and collapse to
   `.active` when the pin no longer has enough rows for the viewport height

To support that flow, the code also extracts:

- `viewportPinActualRowOffset()`

## Call Sites Updated

The shared normalization now runs after the layout-changing paths that can move
the active boundary or remove rows:

- `resize()`
- `resizeWithoutReflow()` for non-reflow completion
- `fixupViewport()` so row-erasure paths keep their old top/active semantics
  and still get the new insufficient-rows guard
- `grow()` after prune/reuse or prune+allocate completion

`grow()` also now clamps a viewport pinned directly to the page being pruned
before that page is reused or destroyed. This prevents the viewport from
holding a stale node reference through the prune path.

## Tests Updated

Adjusted:

- `PageList resize (no reflow) more rows contains viewport`

Added:

- `PageList resize (no reflow) more rows promotes pin viewport to active`
- `PageList grow prune normalizes viewport pinned to pruned page`

These tests cover:

- top/active overlap after row growth
- a true `.pin` entering the active region after a non-reflow resize
- pruning the page that currently owns the viewport pin

## Verification

Commands used for this change:

```bash
zig build test -Dtest-filter='PageList resize (no reflow) more rows contains viewport'
zig build test -Dtest-filter='PageList resize (no reflow) more rows promotes pin viewport to active'
zig build test -Dtest-filter='PageList grow prune normalizes viewport pinned to pruned page'
zig build test -Dtest-filter='prune'
zig build test -Dtest-filter='PageList'
```

## Files

- `src/terminal/PageList.zig`
- `docs/pagelist-viewport-normalization-fix.md`
