# Browser Runtime Activation Model

## Purpose

This document explains the two separate requirements for GhoDex Browser tabs to
render real Chromium content:

1. the app binary must be built with CEF host support enabled
2. a compatible CEF runtime must exist on disk at the configured runtime root

This distinction matters because the Browser UI can still appear even when the
underlying Chromium engine is unavailable.

## The Two Activation Gates

### 1. Host Build Gate

`GhoDex.app` must be compiled with CEF support enabled.

In this repo that means the build must provide:

- `GHODEX_CEF_ENABLED=1`
- a valid `GHODEX_CEF_ROOT`
- a valid `GHODEX_CEF_WRAPPER_LIB`

If this gate is not satisfied, the Browser tab enters
`BrowserRuntimeState.unsupportedBuild` and shows:

`This build of GhoDex was compiled without managed Chromium runtime support.`

Important consequences:

- placing a runtime under `~/Library/Application Support/GhoDex/CEF/current`
  does not fix this state by itself
- merging Browser source changes into `main` does not update any already-built
  `GhoDex.app`
- the supported `nu macos/build.nu` flow now treats CEF as required for the
  main `GhoDex` app build and fails fast if the configured runtime is missing
- the low-level Xcode project defaults still keep `GHODEX_CEF_ENABLED=0`, so a
  plain raw `xcodebuild` or Xcode IDE build can still produce a Browser shell
  without activating Chromium unless the CEF settings are supplied explicitly

### 2. Runtime Supply Gate

Once the app binary supports CEF, GhoDex still needs a compatible runtime on
disk.

Default managed runtime location:

`~/Library/Application Support/GhoDex/CEF/current`

Custom runtime overrides can redirect this to another path through the Browser
settings/config flow.

If the binary is CEF-capable but no compatible runtime is found, the Browser
tab enters `BrowserRuntimeState.runtimeUnavailable`.

If a runtime is found but Chromium still fails to initialize inside the running
app session, the Browser tab enters
`BrowserRuntimeState.initializationFailed`.

## Why A Worktree Build Can Work While Main Still Fails

This was the main source of confusion during Browser development.

The worktree validation flow used explicit CEF-enabled build commands such as:

```bash
xcodebuild -project macos/GhoDex.xcodeproj \
  -scheme GhoDex \
  -configuration Debug \
  SYMROOT=/tmp/ghx-cef-media-build \
  GHODEX_CEF_ENABLED=1 \
  GHODEX_CEF_ROOT=/tmp/ghx-cef-media-build/cef-runtime/current \
  GHODEX_CEF_OTHER_LDFLAGS=-lsqlite3 \
  GHODEX_CEF_WRAPPER_LIB=/tmp/ghx-cef-media-build/cef-runtime/current/lib/Debug/libcef_dll_wrapper.a \
  build
```

That produced an isolated app bundle with the host-build gate satisfied.

After those commits were merged into `main`, any pre-existing installed app or
any fresh low-level raw build could still show `unsupportedBuild` because:

- source merge and binary rebuild are separate steps
- the raw project configuration remains CEF-disabled unless the build is
  explicitly supplied with the CEF inputs

The supported scripted build path is now:

```bash
nu macos/build.nu --configuration Debug --action build
```

That command defaults the main `GhoDex` app to `CEF required`. If the runtime is
missing, the build stops with a clear error instead of silently emitting an
`unsupportedBuild` app. If a Browser-disabled build is intentional, it must now
be explicit:

```bash
nu macos/build.nu --configuration Debug --action build --cef-mode disabled
```

## Failure-State Matrix

| Browser state | What it means | Typical fix |
| --- | --- | --- |
| `unsupportedBuild` | This `GhoDex.app` was built without CEF host support | rebuild the app with `GHODEX_CEF_ENABLED=1` plus valid CEF paths |
| `runtimeUnavailable` | The app supports CEF, but no compatible runtime was found at the configured path | install or point GhoDex at a valid runtime |
| `initializationFailed` | The runtime was found, but Chromium failed to activate in this session | inspect runtime compatibility, helper staging, and initialization logs |
| `ready` | Host build and runtime supply are both satisfied | normal Browser execution |

## Codec Scope

H.264/AAC is a third layer on top of activation, not a substitute for it.

- `unsupportedBuild` means Chromium never started at all
- `runtimeUnavailable` means Chromium-capable app, but no runtime present
- codec failures mean Chromium started, but the supplied runtime lacks the
  proprietary media lane the target site expects

So a codec-enabled runtime does not solve `unsupportedBuild`, and a CEF-enabled
app does not guarantee H.264/AAC playback.

## Recommended Developer Reading Order

1. Read this document to understand the activation gates.
2. Read `browser-tab-codec-runtime-playbook.md` for codec-enabled runtime
   production and validation.
3. Read `browser-tab-completeness-audit.md` for the remaining Browser parity
   gap and current evidence.
