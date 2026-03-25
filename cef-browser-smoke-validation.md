# CEF Browser Smoke Validation

This note records how the macOS CEF browser smoke harness is expected to behave for the `feat/cef-browser-tab` worktree and why the validation flow is structured this way.

## Harness Location

The active smoke harness lives outside the repo at:

`/Users/leongong/Desktop/LeonProjects/gho_workspace/smoke-cef-browser-20260319/run_browser_smoke.py`

That workspace path is intentional because the harness needs a writable scratch area for app logs, config files, extracted runtime fixtures, and smoke result artifacts.

## Goals

The harness validates four things:

1. the managed runtime download URL and SHA from `BrowserPaths.swift`
2. runtime override round-trip from `config.ghodex` into `UserDefaults` and then into CEF startup
3. external profile override round-trip from `config.ghodex` into `UserDefaults` and then into CEF startup
4. browser page-tab routing behavior for popup and `target=_blank` flows

## Stability Rules

The smoke flow is only trustworthy when it follows these rules:

- Resolve the app bundle dynamically from the newest `macos/build-managed-cef*/Debug/GhoDex.app` in the feature worktree so validation always targets the latest local build.
- Kill stale worktree-local GhoDex debug processes before each run. Old browser processes can keep shared Chromium state alive and make a clean launch look like a runtime bug.
- Do not resolve `macos/build/cef-runtime/current` to its real target path when writing the runtime override. The round-trip check must preserve the worktree path that the feature writes into config and defaults.
- Wait for the `[CEF] Initializing` log marker instead of sleeping for a fixed attach window. The fixed-sleep approach was fragile and could misclassify slow or fast launches as failures.
- Treat multiple `[CEF] Initializing` lines in a single launch log as a harness failure signal. That usually means the validation environment is polluted or a process lifecycle assumption is wrong.
- Use a dedicated runtime-only external profile for the runtime override test so the runtime-path assertion does not get mixed with Chromium's managed shared profile state.
- Accept zombie processes as terminated during cleanup. The smoke runner should not fail just because the parent has not reaped a dead child yet.

## Expected Artifacts

A healthy run writes:

- `app-launch.log`
- `smoke-result.json`
- extracted managed-runtime fixture content under `extracted-runtime/`

The most important assertions in `smoke-result.json` are:

- `runtime_roundtrip.first_launch_runtime_root`
- `runtime_roundtrip.second_launch_runtime_root`
- `profile_roundtrip.custom_external_profile`
- `profile_roundtrip.managed_external_profile`
- `page_tab_routing.marker`

For this worktree, the expected runtime root is:

`/Users/leongong/Desktop/LeonProjects/gho_workspace/wt-cef-browser-tab/macos/build/cef-runtime/current`

## Fresh Evidence

The stabilized harness was rerun on `2026-03-19`, and the resulting artifact is:

`/Users/leongong/Desktop/LeonProjects/gho_workspace/smoke-cef-browser-20260319/smoke-result.json`

That run confirmed:

- runtime override round-trips to the worktree runtime path on first and second launch
- custom external profile round-trips to `custom-profile`
- managed-profile mode clears the external profile override
- browser page-tab popup routing still returns `PAGE_TAB_SMOKE_OK`

## Command

From the workspace harness directory:

```bash
python3 /Users/leongong/Desktop/LeonProjects/gho_workspace/smoke-cef-browser-20260319/run_browser_smoke.py
```
