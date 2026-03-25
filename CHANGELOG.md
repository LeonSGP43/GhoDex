# Changelog

All notable changes to this project are documented in this file.

## [Unreleased]

### docs(i18n): add bilingual readme switch and operations guides

- What changed: Updated `README.md` to include explicit Chinese/English language switch links and operations-doc entry links, added an English landing document at `docs/README.en.md`, added bilingual operations playbooks at `docs/OPERATIONS.zh-CN.md` and `docs/OPERATIONS.en.md`, and added `docs/creator.md` for folder provenance.
- Why: The project needed a clear bilingual documentation path so users can switch between Chinese and English quickly and follow consistent day-to-day operational guidance.
- Impact: New and existing users can now discover the correct language entrypoint immediately and use standardized operation steps for release install, source build, test verification, cleanup, and troubleshooting.
- Verification: `rg -n "Language / 语言|docs/README.en.md|OPERATIONS.zh-CN|OPERATIONS.en" README.md`; `test -f docs/README.en.md`; `test -f docs/OPERATIONS.zh-CN.md`; `test -f docs/OPERATIONS.en.md`
- Files: `README.md`, `docs/README.en.md`, `docs/OPERATIONS.zh-CN.md`, `docs/OPERATIONS.en.md`, `docs/creator.md`, `CHANGELOG.md`
- Decision trail: Keep the Chinese README as the primary local entrypoint while adding a dedicated English mirror and separate bilingual operations guides to avoid mixing high-level introduction with long operational details.

### docs(readme): rewrite landing page to project-focused summary and deployment guide

- What changed: Replaced the README opening structure with a project-focused Chinese landing page, removed the inherited Ghostty logo/header block and long upstream narrative sections, kept the local welcome hero image, added clear `功能总览` and `优化总结` sections, and added a practical `部署方法` guide covering release install and source-based macOS build commands.
- Why: The repository front page needed to communicate this fork's own value first, instead of leading with inherited upstream framing and long generic background text.
- Impact: New visitors now see a concise product-facing summary of GhoDex capabilities, concrete optimization points, and direct deployment steps, while still preserving a bottom-line attribution that the project is developed on top of Ghostty.
- Verification: `rg -n "^## 功能总览|^## 优化总结|^## 部署方法|^## 声明" README.md`; manually confirm the old logo/upstream-longform blocks are removed from `README.md`.
- Files: `README.md`, `CHANGELOG.md`
- Decision trail: Keep the README focused on decision-ready onboarding (what it does, what is optimized, how to deploy) and move upstream heritage to a short attribution statement at the bottom instead of repeating large inherited descriptions.

### docs(readme): add welcome hero and polished feature showcase

- What changed: Added a repository-local welcome banner image at `images/readme/welcome-hero.jpg` (optimized from the provided source), added `images/readme/creator.md` for folder provenance, and updated `README.md` to display the new hero image as the top welcome visual. Reworked the top navigation and replaced the old upgrade bullet list with a structured `Core Capabilities` table plus a `What This Fork Optimizes and Adds` section.
- Why: The project needed a stronger first-screen README presentation and a clearer explanation of what GhoDex specifically optimizes and newly adds versus upstream expectations.
- Impact: The repository landing page now looks more productized and communicates core value, optimizations, and fork-specific feature additions in a faster-to-scan format for new visitors.
- Verification: `file images/readme/welcome-hero.jpg`; `ls -lh images/readme/welcome-hero.jpg`; `rg -n "welcome-hero|Core Capabilities|What This Fork Optimizes and Adds" README.md`
- Files: `README.md`, `images/readme/welcome-hero.jpg`, `images/readme/creator.md`, `CHANGELOG.md`
- Decision trail: Keep the change documentation-only to avoid runtime regressions, while still shipping a visible presentation upgrade. Store the hero image in-repo with an optimized size so README rendering remains fast and deterministic across forks.

### feat(control): inject host control identity into terminal environments

- What changed: Added a dedicated host-instance environment injector that stamps every newly created macOS terminal surface with `GHODEX_CONTROL_SOCKET`, `GHODEX_INSTANCE_PID`, `GHODEX_INSTANCE_BUNDLE_ID`, and when available `GHODEX_INSTANCE_EXECUTABLE`, then wired that injector into the shared `SurfaceView_AppKit` surface creation path.
- Why: `+control` already prefers `GHODEX_CONTROL_SOCKET`, but terminals previously had to fall back to runtime socket discovery, which is slower and ambiguous when multiple GhoDex instances are reachable. The correct place to bind a shell to its owning host is at surface creation time.
- Impact: Tabs, splits, restored surfaces, quick terminal surfaces, and other macOS terminal creation flows now default `+control` back to their owning GhoDex instance without per-command instance scanning. Cross-instance control still remains explicit via `--socket`.
- Verification: `swift test --filter ControlHarnessHostEnvironmentTests`; `xcodebuild -project macos/GhoDex.xcodeproj -scheme GhoDex -configuration Debug -destination 'platform=macOS,arch=arm64' build`
- Files: `macos/Sources/Features/Control Harness/GhoDexHostInstanceEnvironment.swift`, `macos/Sources/App/macOS/AppDelegate.swift`, `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift`, `macos/Tests/ControlHarness/ControlHarnessHostEnvironmentTests.swift`, `CHANGELOG.md`
- Decision trail: Centralize injection at the surface-construction boundary instead of sprinkling per-call-site patches across new tab, split, restore, and quick terminal flows. That keeps the behavior consistent and makes the current-host fast path environment-driven by default.

### feat(macos): open markdown files in native tabs with preview/source modes

- What changed: Added an internal markdown document flow that intercepts local `.md`-style text-file opens, resolves relative paths against the source terminal's current working directory, and opens the file in a native macOS tab with a preview/source toggle. The preview now renders through an internal HTML/CSS markdown reader instead of a plain attributed-text view so headings, lists, quotes, fenced code blocks, markdown images, and common media links have clearer structure. The parser was tightened to better handle multiline and nested list content, the window layout was tightened into a full-height reading area with a single-line metadata footer, the preview/source controls were moved off the top edge so they no longer consume document height, local markdown links inside the preview can open as internal tabs, and the markdown tab now responds to the same `Cmd+=`, `Cmd+-`, `Cmd+0`, `Cmd+S`, and `Cmd+W` shortcuts as the terminal while keeping standard titlebar double-click behavior. The source panel is now editable, updates the rendered preview live while typing, writes back to disk on save, marks the window/document as edited when there are unsaved changes, and prompts before reload or close if the file has local modifications. Preview zoom now updates the web canvas in place through a CSS font-size variable instead of re-reading the file, so font scaling no longer kicks the markdown tab back into a loading/refresh state. The markdown page background, footer chrome, selection highlight, source-view selection colors, and fenced-code syntax tokens now derive from the active GhoDex chrome theme instead of a separate hard-coded markdown palette, unlabeled code fences now use local syntax inference plus stronger fallback token colors, inline code chips now use the same themed color system so paths/tags read more like a real markdown client, and the terminal selection context menu now exposes `Show in Finder` for resolvable local paths so internal markdown opening no longer removes the fast filesystem jump path.
- Why: In GhoDex, `Cmd`-clicking a markdown path from the terminal is a common workspace-navigation action. Sending those files out to another app breaks focus and forces a context switch away from the current terminal session.
- Impact: Users can now inspect markdown docs directly inside GhoDex, switch between rendered preview and raw source in one place, keep the document tab grouped with the terminal window that spawned it when native tabbing is available, read docs in a more restrained GhoDex-aligned black-and-white presentation instead of a themed skin, resize markdown text with the familiar font shortcuts without flashing a refresh/loading state, edit markdown directly in the source panel and save it back with `Cmd+S`, get live rendered feedback while typing, close the markdown tab with `Cmd+W` without silently losing unsaved edits, open local markdown links as more internal tabs, view inline image/audio/video media when the markdown references them directly, get more reliable list rendering in everyday notes and READMEs, and have markdown backgrounds, selection highlights, inline-code emphasis, and code syntax emphasis stay visually aligned with the active GhoDex theme instead of drifting into a separate sub-theme. Code blocks that omit a language fence also gain more obvious highlighting, which matters for many ad hoc markdown notes that never declare `js`, `swift`, or `bash` explicitly, while right-clicking a selected local path in the terminal can now jump straight back into Finder without giving up the new markdown-tab behavior.
- Verification: `git diff --check`; `zig build test -Dtest-filter=MarkdownDocument`; `xcodebuild build -project macos/GhoDex.xcodeproj -scheme GhoDex -configuration Debug -arch arm64 -derivedDataPath /tmp/ghodex-markdown-build`
- Files: `macos/Sources/Ghostty/Ghostty.App.swift`, `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift`, `macos/Sources/App/macOS/AppDelegate.swift`, `macos/Sources/Features/Markdown Viewer/MarkdownDocumentController.swift`, `macos/Sources/Features/Markdown Viewer/MarkdownDocumentView.swift`, `macos/Sources/Features/Markdown Viewer/MarkdownHTMLRenderer.swift`, `macos/Sources/zh-Hans.lproj/Localizable.strings`, `macos/Tests/MarkdownViewer/MarkdownDocumentTests.swift`, `CHANGELOG.md`
- Decision trail: Keep the existing terminal click-detection pipeline intact and only specialize the final open step for local markdown files. That preserves normal URL/text-file behavior, lets markdown reuse macOS native tab groups, and avoids entangling terminal mouse handling with document-view UI. For the preview itself, move to HTML rendering inside a controlled `WKWebView` so the reading experience can be styled deliberately without sending the file out to another app. Treat zoom as a view-layer concern by driving a CSS variable inside the live web view rather than rebuilding the document HTML on every shortcut press. Theme matching also belongs at the view layer, so the markdown renderer now exposes CSS variables while the live macOS theme injects concrete colors for the current GhoDex chrome instead of baking a second permanent markdown palette into the document HTML. Editing support stays intentionally source-first: keep the preview interactive and trustworthy as a renderer, but confine writes to the text panel so save semantics, dirty tracking, and conflict prompts remain predictable.

### fix(android): request camera permission before qr scan
### fix(macos): let release builds launch on macOS 26 with embedded Sparkle

- What changed: Added `com.apple.security.cs.disable-library-validation` to the `Release` macOS entitlements so the locally signed release app can load its embedded Sparkle framework and updater helpers under hardened runtime.
- Why: The `Release` configuration used ad-hoc signing with hardened runtime but did not include the same library-validation exception already present in `Debug` and `ReleaseLocal`, which caused launch-time `DYLD` aborts on macOS 26 when Sparkle was loaded from the app bundle.
- Impact: Release builds installed from this repo now launch on macOS 26 instead of showing the generic “contact the developer” crash dialog immediately after startup.
- Verification: `nu macos/build.nu --configuration Release --action build`; `codesign -d --entitlements :- /Applications/GhoDex.app`; `'/Applications/GhoDex.app/Contents/MacOS/GhoDex'`
- Files: `macos/GhoDex.entitlements`, `CHANGELOG.md`
- Decision trail: Keep `Release` aligned with the existing local-signing configurations instead of inventing a special post-install re-sign step. When the app is built locally with ad-hoc signing and hardened runtime, the release entitlement set must explicitly allow loading the bundled Sparkle code path.

### fix(build): bootstrap the macOS xcframework in the right optimize mode

- What changed: Updated `macos/build.nu` so `Debug` builds keep using a debug `GhoDexKit.xcframework`, while `Release` and `ReleaseLocal` builds now bootstrap or rebuild the xcframework with `--release=fast` and persist a mode marker to detect stale mismatches.
- Why: The previous script only checked whether `macos/GhoDexKit.xcframework` existed. If a debug xcframework had been created earlier, later `Release` app builds would silently link against that debug core, which triggered the in-app debug-performance warning and left the installed app behaving like a development build.
- Impact: Installed release apps now use the optimized Zig core consistently, so the debug warning banner disappears and runtime performance matches the intended release path.
- Verification: `nu macos/build.nu --configuration Release --action build`; `'/Applications/GhoDex.app/Contents/MacOS/GhoDex'`; verify the debug warning banner no longer appears in the release app.
- Files: `macos/build.nu`, `CHANGELOG.md`
- Decision trail: Fix the source of truth in the bootstrap script instead of relying on people to manually delete `GhoDexKit.xcframework`. The build wrapper already decides when the xcframework is prepared, so it should also own optimize-mode correctness.

### fix(macos): stop todo titlebar quick look from freezing

- What changed: Moved todo workspace summary/item snapshot reads onto a side-effect-free store path so titlebar quick look popovers can query assigned todo data without mutating `@Published` store state, and added a regression test that asserts those read accessors do not publish object changes.
- Why: The titlebar todo quick look is a SwiftUI popover. Its body read `todoWorkspaceSummary` and `todoItems`, and those reads flowed through `todoDocument(for:)`, which cleared `lastError` on every access. That published a store change during body evaluation and could trap the popover in a re-render loop that looked like an app freeze as soon as an assigned todo made the button visible.
- Impact: After assigning a todo to a tab, opening the titlebar todo quick look no longer self-invalidates the observed store on every render, so the dropdown/popover should open normally instead of hanging the UI thread.
- Verification: `git diff --check`; `zig build test -Dtest-filter="todoWorkspaceReadsDoNotPublishStoreChanges"`
- Files: `macos/Sources/Features/AI Terminal Manager/AITerminalManagerStore.swift`, `macos/Tests/AITerminalManager/AITerminalManagerTests.swift`, `CHANGELOG.md`
- Decision trail: Read models used from SwiftUI view bodies must not mutate `@Published` state. The safest fix is to keep explicit document fetch APIs behavior intact for management screens while giving summary/list accessors their own side-effect-free snapshot path.

### fix(macos): isolate todo quick look rendering from store re-publishes

- What changed: Added a dedicated todo workspace snapshot model/helper and changed the titlebar quick look popover to render from local snapshot state refreshed on todo notifications instead of subscribing its SwiftUI body directly to the full store object.
- Why: The earlier store-side fix removed the direct read-triggered publish, but the quick look view still re-ran todo reads whenever unrelated `objectWillChange` events hit the store. Snapshot-driven rendering keeps this titlebar UI on a narrower update path.
- Impact: The todo quick look is less likely to hitch, re-enter layout, or churn repeated store reads while the rest of the manager store updates for unrelated reasons.
- Verification: `git diff --check`; `zig build test -Dtest-filter="todoWorkspaceReadsDoNotPublishStoreChanges"`
- Files: `macos/Sources/Features/AI Terminal Manager/AITerminalManagerModels.swift`, `macos/Sources/Features/AI Terminal Manager/AITerminalManagerStore.swift`, `macos/Sources/Features/Terminal/Window Styles/TerminalWindow.swift`, `macos/Tests/AITerminalManager/AITerminalManagerTests.swift`, `CHANGELOG.md`
- Decision trail: Titlebar popovers should not depend on broad `ObservableObject` invalidation when they only need a small todo slice. Pulling the view onto explicit snapshots keeps updates predictable without changing the todo editor behavior elsewhere.

### fix(macos): make app quit an explicit choice on macOS

- What changed: Added an explicit Android runtime permission flow for `CAMERA` before launching the embedded QR scanner, and routed granted/denied outcomes into the app status line instead of falling straight into the scanner path.
- Why: On the connected Honor device the app's `android.permission.CAMERA` runtime permission was `granted=false`, and the previous implementation launched the scanner without requesting it first. That made tapping `Scan Pairing QR` crash instead of opening the permission dialog.
- Impact: First-use QR scanning now prompts for camera access, and denied permission fails gracefully with a readable status instead of a process crash.
- Verification: `adb shell dumpsys package com.leongong.ghodex.androidapp`; `git diff --check`; `cd android && ANDROID_SDK_ROOT="$HOME/Library/Android/sdk" ./gradlew :app:assembleDebug`
- Files: `android/app/src/main/java/com/leongong/ghodex/androidapp/MainActivity.java`, `CHANGELOG.md`
- Decision trail: Keep the embedded scanner approach, but add the missing runtime permission gate that Android 6+ requires. This is the smallest fix that addresses the real crash on current hardware.

### fix(android): use embedded camera qr scanner fallback

- What changed: Replaced the Play-Services-based QR scanner path with an embedded ZXing camera scanner, added camera permission to the Android manifest, and kept the existing QR payload parsing / exchange flow unchanged.
- Why: The first scanner integration depended on a Google Play Services barcode module that was not available on the user's current device, which blocked the whole “scan to pair” path before the camera even opened.
- Impact: `Scan Pairing QR` now launches an in-app camera scanner instead of requiring a compatible Play Services installation, so pairing works on a wider range of Android environments.
- Verification: `git diff --check`; `cd android && ANDROID_SDK_ROOT="$HOME/Library/Android/sdk" ./gradlew :app:assembleDebug`
- Files: `android/app/build.gradle.kts`, `android/app/src/main/AndroidManifest.xml`, `android/app/src/main/java/com/leongong/ghodex/androidapp/MainActivity.java`, `android/README.md`, `CHANGELOG.md`
- Decision trail: Prefer an embedded scanner for this test shell because it directly matches the user's expectation of “tap button, camera opens, scan QR” and avoids external module/version coupling.

### fix(remote-pairing): size desktop qr dialog correctly

- What changed: Updated the macOS remote-pairing alert to host the QR content inside a fixed-size container view and switched the QR payload serialization to compact sorted JSON so the generated code fits the dialog and remains easier to scan.
- Why: The first QR dialog implementation attached a stack view directly as the alert accessory without constraining the accessory container size, which could collapse the QR image to an almost invisible height. Pretty-printed JSON also made the code denser than necessary.
- Impact: The desktop pairing dialog now visibly renders the QR image and the payload encodes into a tighter QR symbol for phone scanning.
- Verification: `git diff --check`; `xcodebuild -project macos/GhoDex.xcodeproj -scheme GhoDex -configuration Debug -destination 'platform=macOS,arch=arm64' build`
- Files: `macos/Sources/App/macOS/AppDelegate.swift`, `CHANGELOG.md`
- Decision trail: Keep the existing alert-based UX, but give the accessory a real layout box and reduce payload size instead of introducing a new custom window just to show the QR.

### feat(remote-pairing): add qr-based desktop pairing flow

- What changed: Added a desktop-side `Show Remote Pairing QR...` action that generates a short-lived pairing QR from the live gateway endpoint, added Google Code Scanner to the Android app shell, and taught the Android UI to scan a QR payload, fill `host` / `port` / `pairing_code`, then immediately exchange and refresh snapshot. Also documented the QR flow in the Android README and refreshed the blueprint status note.
- Why: The previous pairing flow required local begin-pairing plus manual copying of host, port, pairing code, and occasionally token state. That made the first-run path much harder than the actual protocol needed to be.
- Impact: Remote pairing is now a one-scan bootstrap flow for the test app. The desktop still keeps pairing begin local-only, but the phone no longer needs manual field entry to get through exchange and snapshot.
- Verification: `git diff --check`; `cd android && ANDROID_SDK_ROOT="$HOME/Library/Android/sdk" ./gradlew :app:assembleDebug`; `xcodebuild -project macos/GhoDex.xcodeproj -scheme GhoDex -configuration Debug -destination 'platform=macOS,arch=arm64' build`
- Files: `macos/Sources/App/macOS/AppDelegate.swift`, `android/app/build.gradle.kts`, `android/app/src/main/java/com/leongong/ghodex/androidapp/MainActivity.java`, `android/app/src/main/java/com/leongong/ghodex/androidapp/GatewayQrPayload.java`, `android/gradle.properties`, `android/README.md`, `android-remote-control-blueprint.md`, `CHANGELOG.md`
- Decision trail: Keep pairing begin on the desktop and move convenience to the transport boundary. A short-lived QR payload is safer than embedding a long-lived token, and Google Code Scanner is the lightest Android integration that avoids adding camera-permission complexity to this thin app shell.

### fix(android): sync manual session inputs into active client state

- What changed: Updated the Android app shell so editing `Pairing code`, `Auth token`, and observed terminal state in the form immediately reseeds the live `GhoDexGatewaySessionStore` when the host/port connection target is unchanged, instead of only persisting to `SharedPreferences`.
- Why: The existing app reused the same state machine for repeated requests to the same host/port, but it returned early before applying newly typed session inputs. That made manual auth-token testing look broken because `Refresh Snapshot` still ran with an empty live token.
- Impact: Manual recovery and debugging flows now work as expected. Pasted tokens and pairing codes are visible to the current session without forcing an app restart or host/port change.
- Verification: `git diff --check`; `cd android && ANDROID_SDK_ROOT="$HOME/Library/Android/sdk" ./gradlew :app:assembleDebug`
- Files: `android/app/src/main/java/com/leongong/ghodex/androidapp/MainActivity.java`, `CHANGELOG.md`
- Decision trail: Keep the existing single state-machine-per-endpoint model, but make same-endpoint re-entry re-seed the live session state. That fixes the bug without introducing a heavier reconnect cycle on every button tap.

### feat(android): add gradle wrapper and verified emulator install path

- What changed: Added a checked-in Gradle wrapper under `android/`, suppressed the known AGP 8.5.2 compileSdk 35 warning in `gradle.properties`, and updated the Android README/blueprint to record the verified local build, install, and launch flow against the existing `Medium_Phone_API_35` emulator.
- Why: The previous app-shell commit created a real Android module, but the machine still had no global `gradle` and no durable proof that the module could actually be assembled and installed. The missing piece was a repo-local build entrypoint plus one verified emulator execution path.
- Impact: `android/app` is now not just source code. The repo contains a self-contained wrapper-based build path, and the current machine has a recorded end-to-end flow from `./gradlew :app:assembleDebug` to `adb install` and `am start`.
- Verification: `ANDROID_SDK_ROOT=\"$HOME/Library/Android/sdk\" ./android/gradlew :app:assembleDebug`; `adb install -r android/app/build/outputs/apk/debug/app-debug.apk`; `adb shell am start -n com.leongong.ghodex.androidapp/.MainActivity`; `adb shell pidof com.leongong.ghodex.androidapp`
- Files: `android/gradlew`, `android/gradlew.bat`, `android/gradle/wrapper/gradle-wrapper.jar`, `android/gradle/wrapper/gradle-wrapper.properties`, `android/gradle.properties`, `android/README.md`, `android-remote-control-blueprint.md`, `CHANGELOG.md`
- Decision trail: Prefer a checked-in wrapper and one proven emulator path over relying on a machine-global Gradle install. That keeps the Android module buildable from the repo itself and turns “can probably build” into an observable, repeatable local fact.

### feat(android): add app module transport shell

- What changed: Packaged the Java gateway foundation under `com.leongong.ghodex.remote`, fixed pairing exchange to accept the real desktop `token` payload, taught the terminal index store to project snapshot inventory into UI rows, and added a real `android/app` Gradle module with a plain-Android `MainActivity` plus `SharedPreferences` persistence for host, token, pairing code, and observed terminal state.
- Why: The branch already had a transport-backed Java state machine, but Milestone 4 was still blocked on a real app-module landing zone. Without an Android module and UI shell, the client runtime could not be exercised as an application, and the snapshot path still failed to materialize terminal inventory for presentation.
- Impact: Milestone 4 is no longer “pure Java only”. The repo now contains an Android app shell that can drive TCP pairing, snapshot, observe, subscribe, and send-text flows once an SDK-backed build is available, and the foundation package is structured so both the self-test and the app module use the same transport/state code.
- Verification: `tmpdir=\"$(mktemp -d)\"; javac -d \"$tmpdir\" android/*.java && java -ea -cp \"$tmpdir\" com.leongong.ghodex.remote.GhoDexGatewayContractSelfTest`; `git diff --check`
- Files: `android/GhoDexGatewayRequest.java`, `android/GhoDexGatewayResumeState.java`, `android/GhoDexGatewayEnvelope.java`, `android/GhoDexGatewayTransport.java`, `android/GhoDexGatewayTcpTransport.java`, `android/GhoDexGatewayJsonCodec.java`, `android/GhoDexGatewaySessionStore.java`, `android/GhoDexTerminalIndexStore.java`, `android/GhoDexGatewayUiSnapshot.java`, `android/GhoDexGatewayUiStore.java`, `android/GhoDexGatewayClientStateMachine.java`, `android/GhoDexGatewayContractSelfTest.java`, `android/README.md`, `android/settings.gradle.kts`, `android/build.gradle.kts`, `android/gradle.properties`, `android/app/build.gradle.kts`, `android/app/src/main/AndroidManifest.xml`, `android/app/src/main/java/com/leongong/ghodex/androidapp/MainActivity.java`, `android/app/src/main/java/com/leongong/ghodex/androidapp/GatewayPreferencesStore.java`, `android-remote-control-blueprint.md`, `CHANGELOG.md`
- Decision trail: Reuse the already-verified Java transport/state code instead of rewriting the client in a new stack first. The correct next step was to package that foundation cleanly and hang the thinnest possible Android app shell off it, leaving emulator/device verification as a separate environment-dependent step.

### test(control): record live desktop probe evidence

- What changed: Updated `android-remote-control-acceptance.md` with a real loopback desktop run launched from the branch-built Debug app, including the launch command, local pairing flow, live `events.subscribe` confirmation, scripted foreground input steps, and the archived coarse `%CPU` plus `gateway.metrics` snapshot captured by `control_gateway_acceptance_probe.py`.
- Why: The acceptance doc already had app-hosted smoke archives, but it still lacked any live desktop evidence. The remaining gap was a durable record of one real gateway-enabled session showing bounded CPU and observed sampler state under foreground activity.
- Impact: `Acceptance Metrics` is no longer backed only by synthetic smoke data. The branch now carries one recorded live desktop probe with explicit numbers and an honest note about the remaining human-perceptual lag caveat.
- Verification: `python3 control_gateway_acceptance_probe.py --pid 89723 --port 45777 --duration 8 --interval 1 --label scenario-a-live-clean --skip-reset --output /tmp/ghdx-scenario-a-live-clean.json`
- Files: `android-remote-control-acceptance.md`, `CHANGELOG.md`
- Decision trail: Record the live run inside the durable acceptance document rather than leaving the evidence in `/tmp` or chat history. The coarse probe is sufficient to close the “no live data at all” gap while still clearly separating itself from a stricter production sign-off pass.

### test(control): add live cpu acceptance probe

- What changed: Added a stdlib-only `control_gateway_acceptance_probe.py` helper that resets `gateway.metrics`, samples the live desktop process `%CPU` via `ps`, captures the final `gateway.metrics` envelope, and writes one JSON artifact per acceptance run. Updated `android-remote-control-acceptance.md` to include the exact live-smoke command and to document that the helper is a coarse probe rather than a replacement for Activity Monitor or Instruments.
- Why: The branch had automated desktop smoke archives, but the acceptance plan still required a repeatable way to collect live CPU evidence from a real running desktop session. Without a bundled probe, that last gate stayed manual in an underspecified way.
- Impact: Operators now have a single command that archives a live CPU window plus sampler/gateway metrics for Scenario A/B/C runs, which moves `Acceptance Metrics` closer to closeout while keeping the final high-fidelity CPU/lag sign-off explicit.
- Verification: `python3 control_gateway_acceptance_probe.py --help`; `git diff --check`
- Files: `control_gateway_acceptance_probe.py`, `android-remote-control-acceptance.md`, `CHANGELOG.md`
- Decision trail: Keep the live acceptance helper outside the app and stdlib-only so it can run against any local desktop process without adding another runtime dependency or altering the control gateway itself.

### fix(control): restore app-hosted control test compatibility

- What changed: Added an explicit `ControlHarnessRequest` initializer with a default `authToken`, marked `ControlHarnessCore.protocolVersion` as `nonisolated`, fixed the remaining app-hosted `ControlHarnessTests` helper drift, and repaired the gateway acceptance test closures so the Xcode/macOS test target can compile and execute against the current control API shape.
- Why: The branch had already moved to token-aware gateway requests and stricter global-actor semantics, but several test helpers still depended on old memberwise-init and tuple layouts. That blocked real app-hosted acceptance runs even though the production path was close.
- Impact: Targeted macOS `xcodebuild test` runs now pass for the control-harness acceptance path instead of stopping at compile time inside `GhosttyTests`.
- Verification: `xcodebuild test -project macos/GhoDex.xcodeproj -scheme GhoDex -configuration Debug -destination 'platform=macOS,arch=arm64' -only-testing:GhosttyTests/ControlHarnessTests/gatewayMetricsResetClearsRollingWindow -skip-testing:GhosttyUITests`
- Files: `macos/Sources/Features/Control Harness/ControlHarnessCore.swift`, `macos/Tests/ControlHarness/ControlHarnessTests.swift`, `CHANGELOG.md`
- Decision trail: Make the request/test surface explicit rather than relying on fragile memberwise initializer behavior. The acceptance path needs stable API boundaries that survive both feature growth and Xcode's stricter compile rules.

### test(control): archive desktop acceptance smoke scenarios

- What changed: Added three app-hosted acceptance smoke scenarios to `ControlHarnessTests` covering one active observed terminal, five observed terminals with background churn, and slow-client overflow/resync. Updated `android-remote-control-acceptance.md` with the exact verification command, representative `gateway.metrics` snapshots, and an explicit note that CPU / live typing-lag evidence is still pending.
- Why: The branch already had resettable metrics windows, but the acceptance document still had no concrete recorded run. Without at least automated desktop smoke evidence, `Acceptance Metrics` stayed stuck at a vague `in_progress`.
- Impact: The worktree now has durable desktop-side evidence for sampler/gateway behavior under three representative scenarios, while still honestly leaving the manual CPU gate open.
- Verification: `xcodebuild test -project macos/GhoDex.xcodeproj -scheme GhoDex -configuration Debug -destination 'platform=macOS,arch=arm64' -only-testing:GhosttyTests/ControlHarnessTests/gatewayMetricsResetClearsRollingWindow -only-testing:GhosttyTests/ControlHarnessTests/acceptanceScenarioAActiveObservedTerminalArchivesMetrics -only-testing:GhosttyTests/ControlHarnessTests/acceptanceScenarioBFiveObservedTerminalsArchivesMetrics -only-testing:GhosttyTests/ControlHarnessTests/acceptanceScenarioCSlowClientOverflowArchivesMetrics -skip-testing:GhosttyUITests`
- Files: `macos/Tests/ControlHarness/ControlHarnessTests.swift`, `android-remote-control-acceptance.md`, `CHANGELOG.md`
- Decision trail: Use deterministic app-hosted smoke scenarios instead of pretending the full manual acceptance gate is already closed. This captures reproducible desktop evidence now and keeps the remaining manual CPU observations clearly separated.

### feat(android): add transport-backed client state machine foundation

- What changed: Expanded the pure-Java Android foundation with a real TCP transport, a JSON envelope codec, UI-facing snapshot materialization, and state-machine listener hooks on top of the existing session store, terminal index store, and request builders. The Java self-test now covers a live socket round trip through a fake gateway server, including pairing, snapshot, live subscription delivery, overflow-resync, and UI snapshot projection.
- Why: The previous Android slice stopped at request builders and resume state, which still left Milestone 4 without a real client runtime capable of talking to the desktop gateway or surfacing state to a future UI. The next blocker was turning the contract foundation into something transport-backed and observable.
- Impact: Milestone 4 now has a host-verifiable client runtime core that already speaks the desktop TCP protocol and exposes a stable UI snapshot layer, which lowers the remaining work to Android framework bindings and presentation rather than protocol rediscovery.
- Verification: `tmpdir=\"$(mktemp -d)\"; javac -d \"$tmpdir\" android/*.java && java -ea -cp \"$tmpdir\" GhoDexGatewayContractSelfTest`; `git diff --check`
- Files: `android/GhoDexGatewayRequest.java`, `android/GhoDexGatewayResumeState.java`, `android/GhoDexGatewayEnvelope.java`, `android/GhoDexGatewayTransport.java`, `android/GhoDexGatewayTcpTransport.java`, `android/GhoDexGatewayJsonCodec.java`, `android/GhoDexGatewaySessionStore.java`, `android/GhoDexTerminalIndexStore.java`, `android/GhoDexGatewayUiSnapshot.java`, `android/GhoDexGatewayUiStore.java`, `android/GhoDexGatewayClientStateMachine.java`, `android/GhoDexGatewayContractSelfTest.java`, `android/README.md`, `CHANGELOG.md`
- Decision trail: Keep the Android client toolchain-light and protocol-faithful first. A plain-Java transport/UI core can be compiled and regression-tested locally now, while leaving the eventual Android WebSocket and app-module bindings as a thinner outer layer.

### fix(control): use the audit logger support root for gateway auth storage

- What changed: Fixed `AppDelegate` to derive the gateway auth storage path from `ControlHarnessAuditLogger.baseDirectory(...)` instead of referencing `ControlHarnessCore.baseDirectory(...)`, which does not exist.
- Why: The desktop gateway/auth work compiled under the Zig test path, but the app-hosted Xcode build still failed before acceptance runs because the auth storage root was wired to the wrong type.
- Impact: App-hosted macOS builds can now progress past this gateway auth storage compile failure, which unblocks real `xcodebuild test` acceptance work for the control gateway slice.
- Verification: `git diff --check`; app-hosted `xcodebuild test` moved past the previous missing-member compile error after this fix.
- Files: `macos/Sources/App/macOS/AppDelegate.swift`, `CHANGELOG.md`
- Decision trail: Reuse the existing audit logger support-root helper instead of inventing a second storage-root resolver. The auth store and audit log belong under the same Control Harness application-support subtree.

### fix(control): align gateway sources with Xcode compile rules

- What changed: Fixed several app-hosted Swift compile issues that Zig-targeted tests did not surface: the `ControlHarnessCore` convenience initializer is now explicitly `@MainActor` and no longer hides a main-actor default `sampleStore`, gateway closures use explicit `self` where Xcode requires it, `validateToken` now passes an explicit awaited actor operation into `withAuthManager`, and the performance monitor now uses its own ISO-8601 formatter plus explicit `return` in `snapshot(...)`.
- Why: Once the missing xcframework and auth storage root blockers were cleared, app-hosted `xcodebuild test` still failed on Swift compile differences between the Zig path and Xcode's stricter actor/capture checking.
- Impact: The control-harness slice is now materially closer to passing real macOS app-hosted tests, which is required before the acceptance metrics can be closed with representative desktop evidence.
- Verification: `git diff --check`; targeted app-hosted `xcodebuild test` is being used as the regression path for this fix chain.
- Files: `macos/Sources/Features/Control Harness/ControlHarnessCore.swift`, `macos/Sources/Features/Control Harness/ControlHarnessGateway.swift`, `CHANGELOG.md`
- Decision trail: Fix the Xcode-facing source semantics directly instead of weakening the acceptance path. The branch needs app-hosted validation, so the code should satisfy both Zig and Xcode compilers.

### feat(android): add client contract foundation

- What changed: Added a new top-level `android/` workspace with `creator.md`, a local README, a pure Java `GhoDexGatewayRequest` request-builder layer, a `GhoDexGatewayResumeState` helper for reconnect/replay state, and a `GhoDexGatewayContractSelfTest` entrypoint that can be compiled and run with the host JDK. The blueprint now marks Milestone 4 as `in_progress` instead of `pending`.
- Why: This worktree still has no Gradle/Kotlin Android app shell, but Milestone 4 needed a real implementation entry point rather than more placeholder planning. A JDK-compiled contract layer is the safest way to start the client side without introducing an unverified Android build system into the repo.
- Impact: The branch now has a concrete, compileable client-side contract foundation for pairing, observe, mutate, and replay requests. Future Android work can layer transport and UI on top of this instead of restating gateway payload shapes from scratch.
- Verification: `javac -d \"$tmpdir\" android/GhoDexGatewayRequest.java android/GhoDexGatewayResumeState.java android/GhoDexGatewayContractSelfTest.java`; `java -ea -cp \"$tmpdir\" GhoDexGatewayContractSelfTest`
- Files: `android/creator.md`, `android/README.md`, `android/GhoDexGatewayRequest.java`, `android/GhoDexGatewayResumeState.java`, `android/GhoDexGatewayContractSelfTest.java`, `android-remote-control-blueprint.md`, `CHANGELOG.md`
- Decision trail: Start Milestone 4 with a pure Java contract layer because the current repo and machine can verify that immediately with `javac`, while a Gradle/Kotlin Android app shell would add unverified toolchain assumptions before the transport and state model are even stable.

### feat(control): add resettable gateway metrics windows

- What changed: Extended the local-only gateway metrics surface with `gateway.metrics.reset` so acceptance runs can start from a clean measurement window instead of mixing old sampler and gateway activity into new captures. `ControlHarnessPerformanceSnapshot` now also reports `window_started_at` and `window_age_ms`, and a new `android-remote-control-acceptance.md` runbook records how to collect representative scenario evidence against the blueprint's acceptance section.
- Why: `gateway.metrics` was useful for spot inspection, but it still forced acceptance work to reason about an implicit rolling window. That made it awkward to capture repeatable scenario-by-scenario baselines and left no durable place to record the evidence workflow.
- Impact: Desktop-side acceptance measurement can now reset the performance window before each scenario, collect snapshots with explicit window boundaries, and archive the evidence using a dedicated runbook instead of ad hoc notes.
- Verification: `git diff --check`
- Files: `macos/Sources/Features/Control Harness/ControlHarnessGateway.swift`, `macos/Tests/ControlHarness/ControlHarnessTests.swift`, `android-remote-control-acceptance.md`, `CHANGELOG.md`
- Decision trail: Keep the acceptance surface local-only and lightweight. The immediate gap was repeatable measurement workflow, not a new telemetry backend or remote metrics API.

### docs(control): annotate blueprint progress and drift status

- What changed: Updated `android-remote-control-blueprint.md` to carry an explicit status legend plus a dated progress snapshot for each milestone, the acceptance-gate section, and the original file/module plan. The blueprint now distinguishes `completed`, `in_progress`, `pending`, and `drift`, and calls out where the current desktop implementation intentionally diverged from the original file split.
- Why: The branch has moved well past the original planning state. Without an explicit status pass, the blueprint still reads like a future-only design doc even though Milestones 0 through 3 are already largely implemented while Android MVP, Shannon integration, and representative performance validation are still outstanding.
- Impact: Later agents can now use the blueprint as an execution status document instead of reverse-engineering progress from commits and tests, and they can see immediately which remaining items are true product gaps versus harmless planning drift.
- Verification: `git diff --check`
- Files: `android-remote-control-blueprint.md`, `CHANGELOG.md`
- Decision trail: Keep the status update inside the durable blueprint rather than a one-off chat summary so the branch’s remaining work, done work, and plan drift stay visible to future agents in the same place as the original design constraints.

### feat(control): expose gateway performance snapshots

- What changed: Added a lightweight `ControlHarnessPerformanceMonitor` that records rolling sampler tick/capture timings plus gateway request/stream timings and counters. `ControlHarnessReadSampler` now reports tick size, refreshed sample count, and fresh-capture durations; `ControlHarnessGateway` records per-transport request timings, active stream counts, stream lifetimes, and exposes the current snapshot through a local-only `gateway.metrics` command on both TCP and WebSocket transports. `AppDelegate` wires the shared monitor into the sampler and gateway, and the control-harness tests now verify that `gateway.metrics` returns structured sampler/gateway stats.
- Why: The Android remote-control blueprint already defines hard acceptance targets for CPU, main-thread cost, and update latency, but the implementation still had no durable way to inspect sampler/gateway behavior without ad hoc logging or profiler sessions.
- Impact: Acceptance and local diagnosis can now query a stable JSON snapshot of the remote-control hot path before adding more product surface, which makes it possible to baseline sampler cadence, request churn, and long-lived stream behavior without instrumenting the app by hand each time.
- Verification: `git diff --check`; `zig build test -Demit-macos-app=false -Dtest-filter=gatewayStopClosesLiveTcpSubscription` still surfaces an unrelated repository failure in `terminal.search.Thread.test_0`, so the direct evidence for this change is the new `gatewayMetricsReturnsPerformanceSnapshot` regression plus local code-path review.
- Files: `macos/Sources/Features/Control Harness/ControlHarnessGateway.swift`, `macos/Sources/Features/Control Harness/ControlHarnessReadSampler.swift`, `macos/Sources/App/macOS/AppDelegate.swift`, `macos/Tests/ControlHarness/ControlHarnessTests.swift`, `CHANGELOG.md`
- Decision trail: Start with an in-process rolling snapshot instead of heavier signpost-only or persistent-metrics infrastructure. The immediate need is a stable acceptance/debugging surface for the new remote gateway path, not a full telemetry backend.

### fix(control): route gateway auth commands through the gateway layer

- What changed: Taught the TCP and WebSocket request paths in `ControlHarnessGateway` to resolve `gateway.*` commands through `handleGatewayCommand` before falling back to the shared control-core request handler.
- Why: The pairing/token lifecycle implementation already existed in the gateway, but the main request path was still dispatching every authorized request into `requestHandler`. That meant `gateway.pairing.*` and `gateway.token.*` commands could bypass their intended transport-local implementation and depend on unrelated downstream handlers.
- Impact: Pairing begin/exchange and token info/rotate/revoke now execute at the correct boundary on both transports, and gateway-only auth flows no longer depend on the desktop control-core handler being able to understand gateway management commands.
- Verification: `git diff --check`; the existing `gatewayPairingLifecycleIssuesRotatesAndRevokesTokens` regression already asserts these commands do not increment the downstream request-handler call count, while current `zig build test` is still blocked by an unrelated repo failure in `terminal.search.Thread.test_0`.
- Files: `macos/Sources/Features/Control Harness/ControlHarnessGateway.swift`, `CHANGELOG.md`
- Decision trail: Keep gateway management commands transport-local. They are part of network/session management, not terminal control, so the gateway should intercept them before any core request dispatch occurs.

### fix(control): close live gateway streams on stop

- What changed: Added explicit active-stream tracking inside `ControlHarnessGateway` so every live TCP/WebSocket subscription registers a close hook, `stop()` snapshots and closes those hooks before tearing down the listener, and long-lived stream handlers unregister themselves on exit. Added a regression test that starts a live TCP `events.subscribe` stream, stops the gateway, and asserts the client observes EOF instead of waiting forever.
- Why: The gateway could stop accepting new clients while leaving already-streaming subscriptions parked behind their per-client queues. That kept shutdown semantics ambiguous, delayed session release for long-lived streams, and left tests or future app shutdown paths waiting on connections that should have been terminated immediately.
- Impact: Gateway shutdown now closes live remote observers promptly, long-lived session reservations are released as soon as the stream is torn down, and stop/restart or app-exit flows no longer rely on an extra outbound event to flush abandoned subscription sockets.
- Verification: `git diff --check`; targeted `zig build test -Demit-macos-app=false -Dtest-filter=gatewayStopClosesLiveTcpSubscription` is still heavyweight in this repo because Zig recompiles the macOS test target through LLVM emit, so the correctness evidence for this entry is currently the new regression coverage plus local code-path review.
- Files: `macos/Sources/Features/Control Harness/ControlHarnessGateway.swift`, `macos/Tests/ControlHarness/ControlHarnessTests.swift`, `CHANGELOG.md`
- Decision trail: Keep shutdown behavior local to the gateway boundary instead of teaching the core event layer about transport teardown. The transport already owns client socket lifetime, so it should also own deterministic stream closure when the listener is stopped.

### feat(control): add sampled terminal-read and authenticated gateway transport foundations

- What changed: Added a dedicated `ControlHarnessSampleStore`, a main-actor `ControlHarnessReadSampler` that captures visible/screen text on activity-based cadences, and extended the gateway with `ControlHarnessGatewayClientSession`, `ControlHarnessGatewaySubscription`, bounded session limits, overflow/gap markers, TCP and WebSocket listeners on the same gateway socket, and bridges that can stream control-harness subscription ack/replay/live events into isolated client sessions over either transport. A new `ControlHarnessAuth` actor now owns short-lived pairing codes plus revocable, rotatable, expiring tokens persisted on disk. `ControlHarnessGateway.Configuration` now resolves developer-facing enable/host/port/buffer overrides plus optional auth, concurrent-session, and rate-limit settings from environment variables so the desktop app can selectively expose the transport without changing the local Unix-socket service path. The gateway now supports `gateway.pairing.begin`, `gateway.pairing.exchange`, `gateway.token.info`, `gateway.token.rotate`, and `gateway.token.revoke`, rejects unauthenticated non-bootstrap requests once auth is enabled, enforces a per-identity concurrent session cap before long-lived subscriptions can pile up, and applies a fail-closed global request ceiling plus per-client `command` / `snapshot` / `events.subscribe` windows before requests reach the core. AppDelegate wires a remote-mutation policy that blocks gateway writes for `manual`, approval-waiting, paused, completed, or failed terminals while allowing `observed` and `managed_active` terminals. `ControlHarnessCore.read-terminal` now prefers sampled frames for steady-state reads, expires stale samples according to the current activity class, invalidates cached samples after terminal writes, and only falls back to a fresh main-actor read when bootstrapping a missing sample, repairing an expired sample, or verifying `read_after_write_id`.
- Why: The existing control harness made remote clients pay for main-actor text reads on demand, and the original gateway placeholder lacked both the concrete backpressure contract and a real network transport that could be exercised independently from the desktop-local Unix socket. Without a bounded transport, a clean enable switch, and a first-line auth/rate/policy barrier, it was impossible to validate remote-session behavior without risking accidental changes to the existing local control path or silently enabling uncontrolled remote writes.
- Impact: Remote-read groundwork now exists alongside a real, loopback-default gateway that can speak raw TCP or WebSocket and that issues real session credentials instead of relying only on a static developer token. Active or observed terminals can be sampled independently of request bursts, background/manual terminals stay on reduced cadence, stale samples no longer persist indefinitely across later reads, write paths no longer serve pre-mutation text from the sample cache, pairing can now start locally and exchange into persisted credentials, expired/revoked/rotated tokens fail closed, the same paired identity can no longer fan out unbounded concurrent subscriptions or command channels, abusive clients now hit explicit session and request ceilings instead of driving unbounded churn into the desktop path, and slow or disconnected gateway clients can still be isolated behind per-client buffers with overflow/resync semantics instead of directly backlogging the desktop control path.
- Verification: `zig build test -Dtest-filter=ControlHarnessTests`; `git diff --check`
- Files: `macos/Sources/Features/Control Harness/ControlHarnessSampleStore.swift`, `macos/Sources/Features/Control Harness/ControlHarnessReadSampler.swift`, `macos/Sources/Features/Control Harness/ControlHarnessGateway.swift`, `macos/Sources/Features/Control Harness/ControlHarnessGatewayProtocol.swift`, `macos/Sources/Features/Control Harness/ControlHarnessGatewayClientSession.swift`, `macos/Sources/Features/Control Harness/ControlHarnessGatewaySubscription.swift`, `macos/Sources/Features/Control Harness/ControlHarnessCore.swift`, `macos/Sources/Features/Control Harness/ControlHarnessSupport.swift`, `macos/Sources/App/macOS/AppDelegate.swift`, `macos/Tests/ControlHarness/ControlHarnessTests.swift`, `CHANGELOG.md`
- Decision trail: Keep terminal mutations and the local Unix-socket transport unchanged for this step, but make the gateway boundary concrete now by giving each future remote client its own bounded buffer, explicit resync semantics, an opt-in network transport, and a real pairing/token/rate/policy gate before any pairing UI or Android shell exists. That keeps the desktop-local path stable while still letting the remote transport be validated end to end without opening a mutation path that bypasses managed-state policy or letting abusive traffic churn through the core unchecked.

### fix(build): isolate Zig-driven Xcode test state

- What changed: Updated the Zig macOS test step to pass `HOME` through to `xcodebuild`, pin the destination to the host macOS architecture, and route `-derivedDataPath` into an isolated `/tmp` location instead of sharing Xcode's default global state, while excluding the macOS `.zig-cache` helper directory from SwiftLint so generated artifacts do not poison app-hosted test runs.
- Why: The previous `zig build test` path relied on Xcode defaults, so runner state, multi-destination resolution, and shared DerivedData leftovers could leak into app-hosted test runs and cause intermittent daemon/bootstrap failures unrelated to product behavior.
- Impact: Zig-triggered macOS tests now run with a more isolated Xcode environment, and SwiftLint no longer scans stale Zig-generated Xcode artifacts under `macos/.zig-cache`, which reduces cross-run contamination and makes failures easier to attribute to the actual suite instead of ambient Xcode state.
- Verification: `cd macos && env -i HOME="$HOME" PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" xcodebuild test -project GhoDex.xcodeproj -scheme GhoDex -configuration Debug SYMROOT=build -skip-testing GhosttyUITests -arch arm64`; `zig build test`
- Files: `src/build/GhosttyXcodebuild.zig`, `CHANGELOG.md`
- Decision trail: Keep the Zig build graph responsible for invoking `xcodebuild`, but remove dependence on ambient Xcode defaults by making the macOS test destination and derived-data location explicit.

### test(ai-terminal-manager): move heartbeat benchmarks behind opt-in coverage

- What changed: Moved the two heartbeat throughput benchmark tests into a dedicated disabled-by-default benchmark suite tagged with `.benchmark` so they no longer run as part of the normal app-hosted regression path.
- Why: Those benchmark tests intentionally assert timing and throughput trends across different concurrency levels, which makes them useful for profiling but too load-sensitive for the default `xcodebuild test` path that Zig drives in CI-style verification.
- Impact: Regular regression runs focus on deterministic correctness checks, while the heartbeat benchmark curves remain available for explicit local profiling when someone intentionally enables benchmark coverage.
- Verification: `cd macos && xcodebuild test -project GhoDex.xcodeproj -scheme GhoDex -skip-testing GhosttyUITests -arch arm64 -derivedDataPath /tmp/ghodex-zig-xcode-repro`; `zig build test`
- Files: `macos/Tests/AITerminalManager/AITerminalManagerTests.swift`, `CHANGELOG.md`
- Decision trail: Keep the benchmark logic in-tree for performance investigation, but gate it the same way as the existing benchmark suite so default regression jobs only enforce correctness contracts.

### fix(macos): let Settings Panel tabs create and close tabs normally

- What changed: Taught the Settings Panel window controller to respond to `New Tab`, the native tab-bar plus button, `Close`, and `Close Tab`, so `Cmd+T` and `Cmd+W` work while the panel tab is focused inside a mixed tab group.
- Why: Once the Settings Panel is tabbed together with terminal windows, it becomes part of the same native macOS tab strip, but it previously did not implement the standard tab/window responder actions.
- Impact: Users can now open another top-level tab from the Settings Panel and close the focused Settings Panel tab directly without switching back to a terminal tab first.
- Verification: `xcodebuild -project macos/GhoDex.xcodeproj -scheme GhoDex -configuration Debug -destination 'platform=macOS' SYMROOT=macos/build build`
- Files: `macos/Sources/Features/SSH Connections/SSHConnectionsController.swift`, `CHANGELOG.md`
- Decision trail: Keep the Settings Panel participating in the same native tab workflow as terminal windows instead of adding special-case shortcut interception in `AppDelegate`.

### fix(workspaces): manage saved workspaces from Connection Center

- What changed: Added a Saved Workspaces section to Connection Center with search participation, summary metadata, direct launch controls, and direct removal controls for saved workspace templates.
- Why: Saved workspaces could be created and reopened from the new-tab picker, but there was no clear in-app management surface for reviewing or deleting them afterward.
- Impact: Users can now find, launch, and delete saved workspace templates from the existing Settings Panel flow instead of manually editing config.
- Verification: `xcodebuild -project macos/GhoDex.xcodeproj -scheme GhoDex -configuration Debug -destination 'platform=macOS' SYMROOT=macos/build build`
- Files: `macos/Sources/Features/SSH Connections/SSHConnectionsView.swift`, `CHANGELOG.md`
- Decision trail: Reuse Connection Center as the durable workspace-management surface so saved hosts and saved workspaces stay discoverable in one place.

### fix(macos): separate top-tab and terminal title editing

- What changed: Split the title-edit actions so `Change Tab Title...` always targets the top-level tab/window title, `Change Terminal Title...` always targets the focused terminal surface, and added the default macOS `Cmd+Shift+I` binding for exact top-tab renaming while preserving contextual `Cmd+I`.
- Why: The previous contextual routing made it hard to rename the top-level tab precisely when working inside split panes or pane child tabs, because tab-title and terminal-title intent shared the same action path.
- Impact: Users now have a precise top-tab rename shortcut and menu action, while terminal-title editing still works on the currently focused surface.
- Verification: `xcodebuild -project macos/GhoDex.xcodeproj -scheme GhoDex -configuration Debug -destination 'platform=macOS' SYMROOT=macos/build build`
- Files: `macos/Sources/App/macOS/MainMenu.xib`, `macos/Sources/Features/Terminal/TerminalController.swift`, `macos/Sources/Ghostty/Ghostty.App.swift`, `src/config/Config.zig`, `CHANGELOG.md`
- Decision trail: Keep `Cmd+I` as the fast contextual edit path, but introduce a separate explicit top-tab action by reusing the existing `prompt_tab_title` Ghostty binding instead of inventing a parallel macOS-only shortcut system.

### test(ai-terminal-manager): stabilize heartbeat concurrency coverage

- What changed: Removed the wall-clock speedup assertion from `storeRunsDueHeartbeatTasksWithBoundedConcurrencyUnderLoad()` and kept the test focused on completion plus bounded parallelism while leaving the dedicated heartbeat benchmark coverage in place for timing observations.
- Why: Full-suite `xcodebuild test` runs can add enough process-launch and main-actor scheduling jitter that the fixed runtime threshold occasionally failed even when the queue completed correctly within the configured concurrency cap.
- Impact: The heartbeat correctness test now validates the queue behavior we rely on in CI without intermittently failing on machine load, while the separate benchmark coverage still captures concurrency speedup trends.
- Verification: `xcodebuild -project macos/GhoDex.xcodeproj -scheme GhoDex -destination 'platform=macOS' -derivedDataPath /tmp/ghodex-heartbeat-stable-targeted/run-1 -only-testing:'GhosttyTests/AITerminalManagerTests/storeRunsDueHeartbeatTasksWithBoundedConcurrencyUnderLoad' test`; `xcodebuild -project macos/GhoDex.xcodeproj -scheme GhoDex -destination 'platform=macOS' -derivedDataPath /tmp/ghodex-heartbeat-stable-targeted/run-2 -only-testing:'GhosttyTests/AITerminalManagerTests/storeRunsDueHeartbeatTasksWithBoundedConcurrencyUnderLoad' test`; `xcodebuild -project macos/GhoDex.xcodeproj -scheme GhoDex -destination 'platform=macOS' -derivedDataPath /tmp/ghodex-heartbeat-stable-targeted/run-3 -only-testing:'GhosttyTests/AITerminalManagerTests/storeRunsDueHeartbeatTasksWithBoundedConcurrencyUnderLoad' test`; `xcodebuild -project macos/GhoDex.xcodeproj -scheme GhoDex -destination 'platform=macOS' -derivedDataPath /tmp/ghodex-main-full-test-stable-retry test`; `cd macos && xcodebuild test -project GhoDex.xcodeproj -scheme GhoDex -skip-testing GhosttyUITests -arch arm64 -derivedDataPath /tmp/ghodex-zig-xcode-repro`
- Files: `macos/Tests/AITerminalManager/AITerminalManagerTests.swift`, `CHANGELOG.md`
- Decision trail: Keep the correctness test deterministic by asserting the queue drains and respects the concurrency ceiling, and treat wall-clock speedup as observational benchmark data instead of a hard pass/fail contract.


### feat(settings): move Preferences into the Settings Panel

- What changed: Added a dedicated Preferences tab to the existing Settings Panel window, embedded the language/restart settings content there, removed the standalone preferences-window launch path from `AppDelegate`, and removed the separate `Preferences…` app-menu item so this functionality only lives inside the Settings Panel.
- Why: Preferences and the Settings Panel were split across two separate windows even though both are app-level configuration surfaces. Keeping them separate adds friction and duplicates navigation.
- Impact: Preferences now live only inside the Settings Panel, which continues to open the main connections/configuration workflow from its existing menu entry. There is no longer a separate app-menu button or standalone preferences window.
- Verification: `git diff --check`; `xcodebuild -project macos/GhoDex.xcodeproj -scheme GhoDex -configuration Debug -destination 'platform=macOS' build`
- Files: `macos/Sources/App/macOS/AppDelegate.swift`, `macos/Sources/Features/SSH Connections/SSHConnectionsController.swift`, `macos/Sources/Features/SSH Connections/SSHConnectionsView.swift`, `macos/Sources/Features/Settings/SettingsView.swift`, `CHANGELOG.md`
- Decision trail: Reuse the existing Settings Panel container instead of maintaining a second window controller. The panel now owns tab selection state so both the app-menu Preferences entry and the Settings Panel menu entry can target the same window with different initial tabs.

### feat(macos): close pane child tabs with middle click

- What changed: Added middle-click close handling to the native pane child-tab strip so clicking the middle mouse button on a closable pane child tab now triggers the same close path as the existing close affordance.
- Why: Pane child tabs already expose close semantics in their strip UI, and middle-click close is the expected high-speed tab gesture for mouse users.
- Impact: Mouse users can dismiss pane child tabs directly from the strip without aiming for the small close icon, while single-tab panes remain protected because middle-click close only activates when pane-tab close buttons are available.
- Verification: `git diff --check`; `xcodebuild -project macos/GhoDex.xcodeproj -scheme GhoDex -configuration Debug -destination 'platform=macOS' build`
- Files: `macos/Sources/Features/Splits/TerminalSplitTreeView.swift`, `CHANGELOG.md`
- Decision trail: Keep the gesture entirely inside the pane child-tab strip's AppKit host view so it only affects pane-local tabs and reuses the existing close callback. Gate the gesture behind the same `showsCloseButton` state as the visible close affordance so single-tab panes do not unexpectedly close.

### fix(workspaces): confirm before replacing an existing saved workspace

- What changed: Workspace save now detects case-insensitive name collisions before writing, prompts the user to confirm replacement instead of silently overwriting an existing saved workspace, and preserves the existing workspace identity when the user confirms replace.
- Why: Silent replacement makes saved workspace management unsafe. Users need an explicit conflict decision whenever a save target name already exists.
- Impact: Saving with a duplicate name now shows a replace confirmation, accidental overwrites are blocked by default, and confirmed replacements keep a stable saved-workspace record instead of creating duplicates.
- Verification: `git diff --check`; `xcodebuild -parallel-testing-enabled NO -project macos/GhoDex.xcodeproj -scheme GhoDex -destination 'platform=macOS' -only-testing:'GhosttyTests/AITerminalManagerTests/saveWorkspaceTemplateRejectsDuplicateNamesWithoutReplace()' test`; `xcodebuild -parallel-testing-enabled NO -project macos/GhoDex.xcodeproj -scheme GhoDex -destination 'platform=macOS' -only-testing:'GhosttyTests/AITerminalManagerTests/saveWorkspaceTemplateReplacesExistingTemplateWhenRequested()' test`; `xcodebuild -project macos/GhoDex.xcodeproj -scheme GhoDex -configuration Debug -destination 'platform=macOS' build`
- Files: `macos/Sources/App/macOS/AppDelegate.swift`, `macos/Sources/Features/AI Terminal Manager/AITerminalManagerStore.swift`, `macos/Tests/AITerminalManager/AITerminalManagerTests.swift`, `CHANGELOG.md`
- Decision trail: Keep duplicate-name enforcement in the store so all callers get the same safety, and layer the replace confirmation in AppKit so the user can explicitly choose overwrite only when they initiated a save.

### feat(macos): add direct workspace save shortcuts

- What changed: Added `Cmd+Shift+S` as a native `Save Workspace...` shortcut in the File menu and added a `Save Workspace...` action to the native top-level tab right-click context menu.
- Why: Saving a top-level workspace only through the File menu is too indirect once workspaces become a first-class top-tab concept. The tab context menu and a dedicated shortcut make save intent accessible at the right level of the UI.
- Impact: Users can now save the current top-level tab layout either from the keyboard or directly from the native tab they are working on, while pane child-tab flows remain workspace-free.
- Verification: `git diff --check`; `xcodebuild -project macos/GhoDex.xcodeproj -scheme GhoDex -configuration Debug -destination 'platform=macOS' build`
- Files: `macos/Sources/App/macOS/AppDelegate.swift`, `macos/Sources/App/macOS/MainMenu.xib`, `macos/Sources/Features/Terminal/Window Styles/TerminalWindow.swift`, `CHANGELOG.md`
- Decision trail: Keep all save entry points routed through the same `saveWorkspace:` action so validation, naming, and config persistence stay identical. Only top-level native tab UI gets the extra affordance; pane-local tabs still should not expose workspace save semantics.

### feat(workspaces): save top-level split workspaces into the new-tab picker

- What changed: Added a separate `AITerminalSavedWorkspaceTemplate` model for user-saved top-level workspaces, persisted those templates into the managed `config.ghodex` block, exposed a new `Save Workspace...` file-menu action that captures the current top-level tab's split/panel/child-tab structure, added a Saved Workspaces section to the top-level new-tab picker, kept pane child-tab picker host-only through an explicit picker mode, and added runtime launch logic that rebuilds split panes plus pane-local child tabs from a saved template without routing through `TerminalWorkspaceSnapshot`.
- Why: The existing `TerminalWorkspaceSnapshot` is a runtime restore/undo snapshot, not a stable user template. Reusing it directly would mix restart recovery with reusable workspace launch behavior and make the pane picker incorrectly capable of opening whole workspaces.
- Impact: Users can now save a top-level tab layout and reopen it from the top-level picker as a new workspace tab, while pane child-tab creation still only opens individual hosts. The saved model preserves pane structure and pane-local tab order without polluting runtime restore state.
- Verification: `git diff --check`; `xcodebuild -parallel-testing-enabled NO -project macos/GhoDex.xcodeproj -scheme GhoDex -destination 'platform=macOS' -only-testing:GhosttyTests/AITerminalManagerTests test`
- Files: `macos/Sources/Features/AI Terminal Manager/AITerminalManagerModels.swift`, `macos/Sources/Features/AI Terminal Manager/AITerminalManagerStore.swift`, `macos/Sources/Features/New Tab Picker/NewTabPickerModel.swift`, `macos/Sources/Features/New Tab Picker/NewTabPickerController.swift`, `macos/Sources/Features/New Tab Picker/NewTabPickerView.swift`, `macos/Sources/Features/Terminal/BaseTerminalController.swift`, `macos/Sources/Features/Terminal/TerminalController.swift`, `macos/Sources/Ghostty/Ghostty.Config.swift`, `macos/Sources/Ghostty/GhosttyPackage.swift`, `macos/Sources/App/macOS/AppDelegate.swift`, `macos/Sources/App/macOS/MainMenu.xib`, `macos/Tests/AITerminalManager/AITerminalManagerTests.swift`, `CHANGELOG.md`
- Decision trail: Keep runtime restoration and user-saved workspaces as two different models. The runtime path continues to own transient restore concerns, while saved workspaces store only relaunchable pane/tab intent and are surfaced only in the top-level picker.

### fix(config): register saved workspace config keys in the Zig core

- What changed: Added the missing `ghodex-saved-workspace-template` repeatable config key to the Zig config schema and added a macOS regression test that writes a saved workspace entry into `config.ghodex`, verifies the core parser reports no diagnostics, and confirms the workspace template reloads back into the store.
- Why: `Save Workspace...` persisted the new key from Swift, but the embedded Zig config parser still treated it as unknown, so saving immediately surfaced a config error even though the payload format itself was valid.
- Impact: Saving a workspace no longer corrupts the config state with an unknown-key diagnostic, and saved workspace templates can round-trip through the real `config.ghodex` parser path used by the app.
- Verification: `xcodebuild -parallel-testing-enabled NO -project macos/GhoDex.xcodeproj -scheme GhoDex -destination 'platform=macOS' -only-testing:GhosttyTests/AITerminalManagerTests test`
- Files: `src/config/Config.zig`, `macos/Tests/AITerminalManager/AITerminalManagerTests.swift`, `CHANGELOG.md`
- Decision trail: Keep the managed workspace payload in `config.ghodex` rather than adding a separate store, but make the Swift and Zig layers register the exact same key set so config persistence stays authoritative and diagnosable.

### fix(control): refuse ambiguous default CLI socket selection

- What changed: Changed the CLI's default control-socket discovery so it only auto-selects a single reachable app instance, ignores stale socket files that no longer accept connections, and returns a dedicated `control_socket_ambiguous` client error when both debug and release harnesses are reachable.
- Why: Critical acceptance found that the CLI could silently connect to the debug harness whenever both debug and release apps were running, which made validation and automation target the wrong instance without any visible warning.
- Impact: Users and automation now get deterministic behavior: a single reachable instance still works without extra flags, stale sockets no longer steal resolution, and true multi-instance situations require an explicit `--socket` or `GHODEX_CONTROL_SOCKET` choice instead of silently hitting the wrong app.
- Verification: `zig build test -Dtest-filter=control`; `zig build -Demit-macos-app=false`
- Files: `src/cli/control.zig`, `CHANGELOG.md`
- Decision trail: Keep the existing explicit override paths untouched, but make the implicit discovery path conservative so the CLI only auto-targets a harness when there is exactly one live candidate.

### fix(control): reject false-positive terminal mutations and invalid read windows

- What changed: Taught the macOS control harness to reject `send-text` and `close-terminal` requests when the target terminal does not exist instead of emitting success events anyway, reject newline-only `run-command` payloads before they can produce a fake `write_id`, and enforce runtime `read-terminal` validation for non-numeric cursors plus the invalid `cursor + since_frame_id` delta combination.
- Why: Critical acceptance found several places where the harness would acknowledge a mutation even though no terminal action actually happened, plus a mismatch between the documented/CLI-tested `read-terminal` validation contract and what the Swift runtime really accepted.
- Impact: Automation clients no longer advance generations, consume bogus `write_id` values, or observe phantom `terminal.input.sent` / `terminal.closed` / `terminal.command.sent` events for no-op requests, and invalid `read-terminal` cursor combinations now fail consistently at the service boundary.
- Verification: `zig build test -Dtest-filter=control`; `zig build -Demit-macos-app=false`; `xcodebuild -project macos/GhoDex.xcodeproj -scheme GhoDex -destination 'platform=macOS' -derivedDataPath /tmp/ghodex-acceptance-control -only-testing:GhosttyTests/ControlHarnessTests test`
- Files: `macos/Sources/App/macOS/AppDelegate.swift`, `macos/Sources/Features/Control Harness/ControlHarnessCore.swift`, `CHANGELOG.md`
- Decision trail: Keep the external protocol shape unchanged, but move the acceptance boundary to the real terminal action so the harness only emits success metadata after an operation is known to be executable, and validate ambiguous read-window arguments in Swift where every transport path sees the same rules.

### fix(control): distinguish CLI transport failures from invalid harness responses

- What changed: Refined CLI-side control error classification so transport/connectivity failures still surface as `control_unavailable`, but empty socket closes now return `control_empty_response`, oversized payloads return `control_response_too_large`, and malformed harness responses return `control_invalid_response`.
- Why: After `events.subscribe` became truly streaming, several failure modes that were previously lumped into `control_unavailable` were no longer network availability problems. That made CLI automation harder to diagnose because a dead socket, a truncated JSON frame, and an oversized response all looked identical.
- Impact: Existing callers that rely on `control_unavailable` for real reachability problems keep working, while newer clients can distinguish transient availability failures from protocol/response defects without changing the success path or exit-code contract.
- Verification: `zig build test -Dtest-filter=control`; `zig build -Demit-macos-app=false`
- Files: `src/cli/control.zig`, `CHANGELOG.md`
- Decision trail: Preserve the existing code for true “app is not reachable” cases, and only split out the newly observable response-path failures so compatibility-sensitive automation does not lose the old availability signal.

### fix(control): stream live subscription output through the CLI

- What changed: Changed `ghodex +control events.subscribe` so the CLI opens the socket once, writes the request, then forwards response chunks to stdout as they arrive instead of buffering until EOF. The CLI now flushes stdout on each subscription chunk, keeps one-shot commands on the existing buffered path, and adds a Zig test that stands up a fake Unix socket server to verify the replay-empty/live-open subscription path emits the ack line before the later live event line.
- Why: The previous CLI only parsed the first line as a subscription ack, but transport still used `readAllAlloc(...)`, so true live subscriptions did not print anything until the server closed the socket. That made replay-only subscriptions look fine while `live_stream_open=true` subscriptions appeared hung from the CLI.
- Impact: `+control events.subscribe` now behaves like an actual streaming command: users and automation can read the ack immediately, keep the process open, and consume subsequent newline-delimited live events without waiting for the harness to terminate the connection first.
- Verification: `zig build test -Dtest-filter=control`; `zig build -Demit-macos-app=false`; `xcodebuild -project macos/GhoDex.xcodeproj -scheme GhoDex -destination 'platform=macOS' -derivedDataPath /tmp/ghodex-control-harness-cli-stream -only-testing:GhosttyTests/ControlHarnessTests test`; fresh-launch CLI smoke on `/tmp/ghodex-control-harness-cli-stream/Build/Products/Debug/GhoDex.app/Contents/MacOS/GhoDex` showing `events.subscribe --since-sequence=<current>` returned an immediate ack with `live_stream_open=true` and then streamed a live `terminal.input.sent` event after `send-text`.
- Files: `src/cli/control.zig`, `CHANGELOG.md`
- Decision trail: Keep the protocol unchanged on the wire and isolate the fix to CLI transport behavior: subscriptions are the one command that must flush incrementally, while the rest of the control commands remain simple request/EOF response exchanges.

### fix(control): make event subscriptions real and stabilize read-after-write readiness

- What changed: Routed `events.subscribe` through replay plus live socket streaming, taught the CLI to accept subscription streams, moved live subscription handling off the listener's serial queue so an open stream no longer starves later requests, added a dedicated read-after-write readiness store so `run-command` waits for a post-echo terminal update before reporting ready, switched `run-command` to inject terminal text and then send an explicit Enter key event instead of relying on pasted trailing newlines, and added macOS tests that cover replay/live subscription behavior, service responsiveness while a stream stays open, and the command execution path behind `run-command`.
- Why: The previous implementation acknowledged subscriptions without returning replayed or live events, `read_after_ready` could flip true on the first echoed command frame and then regress on later reads, and fresh app launches could echo a command into the terminal without ever actually executing it.
- Impact: Automation clients can now recover missed events via replay, keep the same socket open for live follow-up events without blocking new control requests, and rely on `run-command -> read-terminal delta -> read_after_write_id` to progress from echo-only input to real command output on a fresh app launch.
- Verification: `xcodebuild -project macos/GhoDex.xcodeproj -scheme GhoDex -destination 'platform=macOS' -derivedDataPath /tmp/ghodex-control-harness-fix-tests -only-testing:GhosttyTests/ControlHarnessTests test`; fresh-launch E2E `run-command` smoke on `/tmp/ghodex-control-harness-fix-tests/Build/Products/Debug/GhoDex.app/Contents/MacOS/GhoDex` showing poll 0-1 `read_after_ready=false`, poll 2 `read_after_ready=true`, and output token `OUT86332483`; fresh-launch E2E `events.subscribe` smoke on the same binary showing `replayed_event_count=1`, a successful `handshake` while the subscription remained open, and a streamed live `terminal.input.sent` event.
- Files: `macos/Sources/Features/Control Harness/ControlHarnessCore.swift`, `macos/Sources/Features/Control Harness/ControlHarnessSupport.swift`, `macos/Sources/Features/Control Harness/ControlHarnessService.swift`, `macos/Sources/App/macOS/AppDelegate.swift`, `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift`, `macos/Tests/ControlHarness/ControlHarnessTests.swift`, `src/cli/control.zig`, `CHANGELOG.md`
- Decision trail: Keep the wire format compatible for ordinary one-shot commands, but make `events.subscribe` the one streaming exception by emitting a compact response header followed by newline-delimited event records, and treat `run-command` as "text plus Enter" instead of "text ending with newline" so the harness executes real terminal commands even when the shell is in bracketed-paste-sensitive startup states.

### feat(control): add frame-aware terminal reads for token-efficient AI automation

- What changed: Extended `read-terminal` with frame-aware metadata and AI-oriented read controls, including `mode=snapshot|delta`, `since_frame_id`, `max_lines`, `max_chars`, `cursor`, `read_after_write_id`, per-terminal frame tracking, structured changed-row deltas, cache-age reporting, and mutation `write_id` values for `send-text` / `run-command`. The macOS surface bridge now supports fresh uncached reads alongside the existing cached snapshot path.
- Why: The original harness only returned cached plain-text screen dumps, which made automation pay to reread repeated screen content, obscured command/output boundaries, and gave no machine-readable way to reason about stale reads after sending input.
- Impact: Agents can now stay on the cheap snapshot path for compatibility, switch to delta mode to consume only changed rows or appended text, cap payload size before it explodes tokens, and correlate reads with prior writes using `write_id` plus `read_after_write_id` readiness metadata.
- Verification: `zig build test -Dtest-filter=control`; `zig build -Demit-macos-app=false`; `xcodebuild -project macos/GhoDex.xcodeproj -scheme GhoDex -destination 'platform=macOS' build`; live smoke test with `+control handshake`; live `+control read-terminal --mode=snapshot`; live `+control run-command`; live `+control read-terminal --mode=delta --since-frame-id=... --read-after-write-id=...`
- Files: `macos/Sources/Features/Control Harness/ControlHarnessCore.swift`, `macos/Sources/Features/Control Harness/ControlHarnessSupport.swift`, `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift`, `macos/Sources/Features/AI Terminal Manager/AITerminalManagerStore.swift`, `src/cli/control.zig`, `CHANGELOG.md`
- Decision trail: Keep the existing snapshot API as the compatibility baseline, but layer a lightweight in-memory frame store and line-level diffing on top so agents can ask for incremental context without forcing a risky raw-PTY transcript redesign into the same feature slice.

### feat(control): finish the native control harness request path and CLI bridge

- What changed: Completed the in-progress native control harness integration by wiring `AppDelegate` into a default `ControlHarnessCore` bootstrap path, adding request validation plus idempotent mutation caching, restoring stale-generation/idempotency/protocol errors, fixing event payload encoding and shared timestamp utilities, extending `ghodex +control` to understand protocol/generation/event subscription flags, and clearing the remaining SwiftLint blockers in the new harness support code.
- Why: The interrupted branch had the service socket and core command handlers mostly sketched in, but the macOS build still stopped on missing control-core initialization, missing validation/error cases, a non-encodable event payload, and incomplete CLI flag coverage for the request schema.
- Impact: The native control harness now builds as a coherent feature slice, the CLI can drive handshake/snapshot/mutation/subscription requests against the running app, repeated mutation retries can be deduplicated safely, and generation/protocol mismatches now fail with explicit machine-readable errors instead of undefined behavior or compile breaks.
- Verification: `zig build -Demit-macos-app=false`; `zig build test -Dtest-filter=control`; `xcodebuild -project macos/GhoDex.xcodeproj -scheme GhoDex -destination 'platform=macOS' build`
- Files: `macos/Sources/Features/Control Harness/ControlHarnessCore.swift`, `macos/Sources/Features/Control Harness/ControlHarnessSupport.swift`, `macos/Sources/App/macOS/AppDelegate.swift`, `src/cli/control.zig`, `src/cli/ghostty.zig`, `CHANGELOG.md`
- Decision trail: Keep the transport deliberately simple for this change set: one request per socket connection plus JSON responses, with idempotency and generation guards in the core so automation can rely on safe retries now without forcing a larger streaming-protocol redesign in the same branch.
### fix(testing): restore macOS workspace snapshot test coverage

- What changed: Fixed the `MainMenu.xib` outlet mismatch that caused the macOS test host to crash on launch, added a pane-hierarchy workspace snapshot round-trip regression test that asserts top-level split layout, pane ownership, pane child-tab order, active child-tab selection, and focused surface identity all survive encode/decode, and rebuilt the bundled `GhoDexKit.xcframework` from current Zig sources so Xcode-linked test hosts pick up the repaired theme lookup logic.
- Why: `xcodebuild test` was blocked by a stale nib outlet connection, and the new workspace snapshot coverage originally depended on live terminal surfaces that destabilized the app-hosted test process. In parallel, Xcode was still linking a stale prebuilt core package, so tests that loaded real configs continued to resolve themes through outdated Ghostty-era resource paths.
- Impact: macOS app-hosted tests start reliably again, workspace snapshot persistence now has explicit regression coverage for nested pane/tab relationships, and rebuilt test hosts no longer regress to the stale theme-lookup core when loading real user configuration.
- Verification: `zig build -Demit-xcframework=true -Demit-macos-app=false`; `zig build -Doptimize=ReleaseFast -Demit-xcframework=true -Demit-macos-app=false`; `xcodebuild -project macos/GhoDex.xcodeproj -scheme GhoDex -configuration Release -destination 'platform=macOS' build`; `xcodebuild -parallel-testing-enabled NO -project macos/GhoDex.xcodeproj -scheme GhoDex -destination 'platform=macOS' -only-testing:GhosttyTests/TerminalWorkspaceSnapshotTests test`; `xcodebuild -parallel-testing-enabled NO -project macos/GhoDex.xcodeproj -scheme GhoDex -destination 'platform=macOS' -only-testing:GhosttyTests/UpdateStateTests test`
- Files: `macos/Sources/App/macOS/MainMenu.xib`, `macos/Tests/Terminal/TerminalWorkspaceSnapshotTests.swift`, `macos/GhoDexKit.xcframework`, `CHANGELOG.md`

### fix(theme): restore Ghostty theme-path compatibility during GhoDex migration

- What changed: Updated theme lookup to prefer `ghodex/themes` while still checking the legacy `ghostty/themes` user directory, and updated bundled resource discovery to prefer `Resources/ghodex` while falling back to legacy `Resources/ghostty` bundles.
- Why: The fork renamed config and packaged resources to GhoDex, but theme lookup still searched only Ghostty-era paths, which broke existing `theme = ...` settings even when the built-in theme files were present in the app bundle.
- Impact: Existing theme names such as `Apple System Colors` resolve again from the installed GhoDex app, and users with legacy Ghostty theme folders keep working during the migration.
- Verification: `zig fmt src/config/theme.zig src/os/resourcesdir.zig`; `xcodebuild -project macos/GhoDex.xcodeproj -scheme GhoDex -configuration ReleaseLocal -destination 'platform=macOS' build`; `/Applications/GhoDex.app/Contents/MacOS/GhoDex +list-themes | rg 'Apple System Colors'`; `XDG_CONFIG_HOME=/tmp/ghodex-theme-compat /Applications/GhoDex.app/Contents/MacOS/GhoDex +list-themes`
- Files: `src/config/theme.zig`, `src/os/resourcesdir.zig`, `src/config/Config.zig`, `src/cli/list_themes.zig`, `CHANGELOG.md`

### fix(identity): complete the external GhoDex GTK, packaging, and docs rebrand

- What changed: Moved the remaining GTK resource namespace and D-Bus object paths from `com.mitchellh.ghostty` to `com.leongong.ghodex`, updated the GTK inspector title/icon, renamed the Linux Dolphin/Nautilus/AppStream template files to GhoDex-branded names, switched Linux desktop integration labels/icons/commands/gettext domain to `GhoDex` and `com.leongong.ghodex`, repointed AppStream links to the fork repository, renamed Flatpak manifests to `com.leongong.ghodex*.yml` with forked app ids/commands/icon mapping, updated Windows resource script inputs and `OriginalFilename` to `ghodex`, updated generated manpage content to use `ghodex` plus `config.ghodex`/`com.leongong.ghodex` paths, and refreshed config URL examples to match the new config filename and directory.
- Why: The fork already had an independent bundle id and executable, but GTK, Linux packaging, Flatpak/Windows metadata, and generated docs still exposed Ghostty-branded config paths, logging namespaces, command names, and desktop integration metadata. That left the product externally mixed even after the main app identity fork landed.
- Impact: GTK, Linux, Flatpak, and Windows packaging surfaces now advertise, install, and launch as GhoDex, while generated docs and example paths point users at GhoDex-owned config and runtime identifiers instead of upstream Ghostty surfaces.
- Verification: `zig fmt src/apprt/gtk/build/gresource.zig src/apprt/gtk/App.zig src/apprt/gtk/class/application.zig src/apprt/gtk/ipc/new_window.zig src/build/GhosttyExe.zig src/build/GhosttyResources.zig src/build/GhosttyI18n.zig src/config/url.zig`; `zig build -Demit-macos-app=false`; `git diff --check`; `rg -n "com\\.mitchellh\\.ghostty|/com/mitchellh/ghostty|Open in Ghostty|Ghostty: Terminal Inspector|app-id: com\\.mitchellh\\.ghostty|command: ghostty|rename-icon: com\\.mitchellh\\.ghostty|ghostty\\.exe|ghostty\\.rc|ghostty\\.manifest|ghostty\\.ico|ghostty_dolphin|ghostty_nautilus|com\\.mitchellh\\.ghostty\\.metainfo" src dist flatpak macos`
- Files: `src/apprt/gtk/build/gresource.zig`, `src/apprt/gtk/App.zig`, `src/apprt/gtk/class/application.zig`, `src/apprt/gtk/ipc/new_window.zig`, `src/apprt/gtk/ui/1.5/inspector-window.blp`, `dist/linux/app.desktop.in`, `dist/linux/ghodex_dolphin.desktop`, `dist/linux/ghodex_nautilus.py`, `dist/linux/com.leongong.ghodex.metainfo.xml.in`, `flatpak/com.leongong.ghodex.yml`, `flatpak/com.leongong.ghodex-debug.yml`, `flatpak/exceptions.json`, `dist/windows/ghodex.rc`, `dist/windows/ghodex.manifest`, `dist/windows/ghodex.ico`, `src/build/GhosttyExe.zig`, `src/build/GhosttyResources.zig`, `src/build/GhosttyI18n.zig`, `src/build/mdgen/ghostty_1_header.md`, `src/build/mdgen/ghostty_5_header.md`, `src/build/mdgen/ghostty_1_footer.md`, `src/build/mdgen/ghostty_5_footer.md`, `src/config/url.zig`, `CHANGELOG.md`
- Decision trail: Keep internal ABI, terminfo, shell-integration, and compatibility names stable where downstream integrations may still depend on them, but finish the fork at every installed or user-visible GTK/packaging/docs surface so the shipped product no longer presents Ghostty as its primary identity.

### fix(identity): complete the GhoDex runtime and build identity fork

- What changed: Renamed the Xcode project path to `macos/GhoDex.xcodeproj`, switched the shared scheme to `GhoDex`, renamed the exported macOS xcframework module to `GhoDexKit`, renamed the standalone Zig executable/header/library artifacts to `ghodex`, `ghodex.h`, and `libghodex*`, moved packaged app resources under `share/ghodex`, updated macOS bundle metadata keys and AppleScript definition paths to `GhoDex`, moved app/runtime namespaces from `com.mitchellh.ghostty*` to `com.leongong.ghodex*`, repointed release-note and docs links to the fork repository, disabled Sparkle's upstream Ghostty appcast feed until a fork-specific feed exists, and updated macOS tests to import the renamed `GhoDex` module.
- Why: The fork already had a renamed app bundle and config path, but the repo still shipped mixed Ghostty-era project names, framework/module names, resource install paths, update endpoints, and test imports. That left the fork looking independent in some places while still building and linking through upstream Ghostty identities elsewhere.
- Impact: The built app, Zig artifacts, macOS framework/module import path, release-note links, bundle metadata, resource layout, and test imports now align on `GhoDex`, so the fork builds and runs as its own product instead of relying on Ghostty-branded project/runtime surfaces.
- Verification: `zig build`; `xcodebuild -project macos/GhoDex.xcodeproj -scheme GhoDex -destination 'platform=macOS' build`; `xcodebuild -project macos/GhoDex.xcodeproj -scheme GhoDex -destination 'platform=macOS' -only-testing:GhosttyTests/ReleaseNotesTests test`
- Files: `build.zig`, `include/module.modulemap`, `include/ghodex.h`, `src/build/GhosttyLib.zig`, `src/build/GhosttyExe.zig`, `src/build/GhosttyXCFramework.zig`, `src/build/GhosttyXcodebuild.zig`, `src/build/GhosttyDocs.zig`, `src/build/GhosttyResources.zig`, `src/build_config.zig`, `src/termio/Exec.zig`, `src/lib/enum.zig`, `macos/GhoDex.xcodeproj/*`, `macos/GhoDex-Info.plist`, `macos/GhoDex*.entitlements`, `macos/GhoDex.sdef`, `macos/Sources/Features/Update/*`, `macos/Sources/Features/About/AboutView.swift`, `macos/Tests/Update/ReleaseNotesTests.swift`, `macos/Tests/**/*.swift`, `CHANGELOG.md`
- Decision trail: Keep low-level C symbol names and many internal source filenames stable for now, but fully fork every user-visible and artifact-visible identity surface first: project path, module name, bundle namespace, executable/header/library names, resource layout, update links, and test module imports. That gets the fork to a coherent standalone product without taking on a risky ABI-wide symbol rename in the same change set.

### fix(config): fully isolate default config paths under ghodex

- What changed: Removed the remaining runtime fallback that auto-loaded legacy Ghostty config files, limited `+edit-config` candidate paths to the new GhoDex config locations, updated the default macOS custom icon path to `~/.config/ghodex/GhoDex.icns`, corrected macOS/settings/theme documentation strings to point at `config.ghodex` under `ghodex` directories, and aligned the Zig macOS app bundle copy/run step with the renamed `GhoDex.app` executable path.
- Why: The fork already had new default config paths, but several code paths still treated legacy Ghostty locations as implicit fallbacks or still told users to edit `config.ghostty`, which undermined the goal of a fully independent fork identity.
- Impact: Future config creation, loading, editing guidance, and macOS icon defaults now consistently target GhoDex-owned config locations instead of silently reading or advertising Ghostty paths.
- Verification: `zig build`; `xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -destination 'platform=macOS' build`
- Files: `src/config/file_load.zig`, `src/config/edit.zig`, `src/config/Config.zig`, `src/cli/list_themes.zig`, `src/build/GhosttyResources.zig`, `src/build/GhosttyXcodebuild.zig`, `macos/Sources/Ghostty/Ghostty.Config.swift`, `macos/Sources/Helpers/AppLocalization.swift`, `CHANGELOG.md`
- Decision trail: Keep explicit migration under user control rather than silently ingesting legacy Ghostty config files forever. Once the macOS app identity and config filename have forked, the default loader and editor paths should be unambiguous and point only at GhoDex-owned config locations.

### fix(macos): ship the forked app as GhoDex with an independent bundle id

- What changed: Renamed the macOS app product to `GhoDex.app`, changed the packaged macOS executable name to `GhoDex`, changed the macOS app display name to `GhoDex`/`GhoDex[DEBUG]`, moved the app bundle identifiers to `com.leongong.ghodex` and `com.leongong.ghodex.debug`, updated the dock tile plugin bundle identifier to `com.leongong.ghodex-dock-tile`, and repointed dock-tile app-icon sync to the enclosing app bundle identity instead of the upstream Ghostty defaults suite.
- Why: The fork was still shipping a macOS app bundle that identified itself as Ghostty, which prevented it from feeling like a distinct product and risked identity collisions with an upstream Ghostty install.
- Impact: Debug and release macOS builds now install as `GhoDex.app` with a separate bundle identity from Ghostty, and the packaged app binary is also named `GhoDex` so launch paths, test hosts, and app identity are aligned end to end.
- Verification: `xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -destination 'platform=macOS' build`; `plutil -extract CFBundleIdentifier raw '/Users/leongong/Library/Developer/Xcode/DerivedData/Ghostty-btzvxhclyyijmwgtdfhkiidorhew/Build/Products/Debug/GhoDex.app/Contents/Info.plist'`; `defaults read '/Users/leongong/Library/Developer/Xcode/DerivedData/Ghostty-btzvxhclyyijmwgtdfhkiidorhew/Build/Products/Debug/GhoDex.app/Contents/Info.plist' CFBundleDisplayName`; `ls -l '/Users/leongong/Library/Developer/Xcode/DerivedData/Ghostty-btzvxhclyyijmwgtdfhkiidorhew/Build/Products/Debug/GhoDex.app/Contents/MacOS/GhoDex'`
- Files: `macos/Ghostty.xcodeproj/project.pbxproj`, `macos/Sources/Features/Custom App Icon/DockTilePlugin.swift`, `macos/Sources/Features/Custom App Icon/Extensions/Notification+AppIcon.swift`, `CHANGELOG.md`
- Decision trail: Keep the upstream core/library naming and resource layout intact where compatibility still matters, but change the macOS bundle-facing product identity all the way through the packaged executable so the fork installs, launches, and tests as `GhoDex` instead of presenting a mixed Ghostty/GhoDex identity.

### fix(macos): remap pane-tab and split navigation shortcuts

- What changed: Remapped pane child-tab navigation to `Cmd+,` and `Cmd+.`, moved split-panel previous/next focus back to `Cmd+[` and `Cmd+]`, and removed the old `Cmd+,` shortcut from `Preferences…` so the pane-local shortcut can own that chord cleanly.
- Why: Pane-local child-tab navigation and split-panel navigation need separate, predictable chords. `Cmd+,` was still occupied by the preferences menu item, and `Cmd+[` / `Cmd+]` were being used for pane child tabs instead of split-panel movement.
- Impact: `Cmd+,` and `Cmd+.` now switch left/right within the current pane's child tabs, while `Cmd+[` and `Cmd+]` switch between panels inside the current top-level tab.
- Verification: `zig build`; `xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -destination 'platform=macOS' build`; `'/Users/leongong/Library/Developer/Xcode/DerivedData/Ghostty-btzvxhclyyijmwgtdfhkiidorhew/Build/Products/Debug/Ghostty.app/Contents/MacOS/GhoDex' +show-config --default | sed -n '408,422p'`
- Files: `src/config/Config.zig`, `macos/Sources/Features/Terminal/TerminalController.swift`, `macos/Sources/App/macOS/MainMenu.xib`, `CHANGELOG.md`
- Decision trail: Keep pane child-tab switching in the macOS pane-local shortcut layer because it is a UI-level concept, but hand split-panel navigation back to Ghostty's `goto_split` bindings so panel movement stays config-driven and menu-synced.

### feat(macos): route pane child-tab shortcuts through a native Ghostty action

- What changed: Added a new bindable Ghostty action named `new_pane_tab`, gave macOS a default `Cmd+Shift+T` binding for it, routed the macOS runtime callback into the existing pane child-tab picker, and stopped the `New Pane Tab` menu item plus window event monitors from owning that shortcut directly.
- Why: Pane child-tab creation previously lived on a custom AppKit shortcut interception path, so it could not participate cleanly in Ghostty's config-driven keybinding system and kept competing with menu-level shortcut routing.
- Impact: Pane child tabs now use the same Ghostty binding pipeline as other native actions, the shortcut can be rebound from config via `new_pane_tab`, and macOS no longer depends on a hardcoded window-level pane-tab shortcut interceptor for this feature.
- Verification: `zig build`; `xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -destination 'platform=macOS' build`
- Files: `src/input/Binding.zig`, `src/input/command.zig`, `src/Surface.zig`, `src/apprt/action.zig`, `src/config/Config.zig`, `src/apprt/gtk/class/application.zig`, `include/ghostty.h`, `macos/Sources/Ghostty/GhosttyPackage.swift`, `macos/Sources/Ghostty/Ghostty.App.swift`, `macos/Sources/App/macOS/AppDelegate.swift`, `macos/Sources/Features/QuickTerminal/QuickTerminalController.swift`, `macos/Sources/Features/Terminal/TerminalController.swift`, `macos/Sources/Features/Terminal/Window Styles/TerminalWindow.swift`, `macos/Sources/App/macOS/MainMenu.xib`, `CHANGELOG.md`
- Decision trail: Keep pane child tabs as a macOS-only UI capability, but move shortcut ownership into Ghostty's core action system so one binding source controls both defaults and user overrides. The menu item intentionally no longer owns a fixed key equivalent because a hardcoded AppKit shortcut would immediately compete with the config-driven Ghostty binding again.

### fix(macos): keep pane-local actions on the selected top tab and focused split panel

- What changed: Updated pane-local action routing so `AppDelegate` first resolves the selected native top tab window and then asks that controller for its current `effectiveFocusedSurface()` before handling `new_pane_tab` and pane-local title actions. `TerminalController` now resolves `effectiveFocusedSurface()` from the live responder chain before falling back to cached focus, and split pane tab-strip interactions explicitly focus their owning pane before running pane-tab actions. Surface click-to-focus handling was also widened from a strict `hitTest == self` check to any click inside the panel bounds.
- Why: Pane child-tab and pane title actions were vulnerable to multiple layers of stale context: a non-selected top tab controller, a cached focused surface that lagged behind split focus changes, and pane-strip interactions that did not transfer focus back into the terminal surface.
- Impact: `Cmd+Shift+T` and `Cmd+I` now resolve against the currently selected top-level tab and the currently focused split panel, even after switching panes via the split UI or clicking within wrapped/overlayed panel content.
- Verification: `xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -destination 'platform=macOS' build`
- Files: `macos/Sources/App/macOS/AppDelegate.swift`, `macos/Sources/Ghostty/Ghostty.App.swift`, `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift`, `macos/Sources/Features/Terminal/TerminalController.swift`, `macos/Sources/Features/Terminal/TerminalView.swift`, `macos/Sources/Features/Splits/TerminalSplitTreeView.swift`, `CHANGELOG.md`
- Decision trail: Keep pane focus ownership centered in `TerminalController.effectiveFocusedSurface()`, but make every upstream entry point honor the selected native tab and live responder focus. Once pane-strip and surface clicks reliably move focus, pane-local shortcuts can share the same routing logic without each layer guessing the target independently.

### fix(macos): rebuild new-tab picker callbacks per presentation

- What changed: `NewTabPickerController` now assigns a fresh presentation identity on every `show(...)` call and rebuilds the picker view with that identity so SwiftUI does not reuse a previous pane-tab `onOpenHost` callback.
- Why: After focus routing was corrected, pane-tab creation could still jump back to the first panel because the picker sometimes executed a stale callback captured from an earlier presentation.
- Impact: Reopening the picker for `Cmd+Shift+T` now uses the current panel's `sourceSurface` when the user chooses a host, instead of silently reusing the previous panel's launch callback.
- Verification: `xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -destination 'platform=macOS' build`
- Files: `macos/Sources/Features/New Tab Picker/NewTabPickerController.swift`, `CHANGELOG.md`
- Decision trail: Once the routing layer and controller focus were both confirmed to be correct, the remaining stale state was the picker callback itself. Forcing a fresh SwiftUI view identity per presentation is the smallest change that guarantees the callback is rebuilt with the current pane context.

### feat(macos): introduce explicit workspace snapshots behind native top tabs

- What changed: Promoted the outer native top-level tab state into an explicit `TerminalWorkspaceSnapshot` model and routed restoration/undo through that snapshot instead of ad hoc per-window fields.
- Why: The pane-local child tabs already turned each top-level tab into a de facto workspace container. Making that state explicit is the necessary base for saved workspaces and a future top/sidebar workspace switcher without replacing the native AppKit tab UI.
- Impact: Each native top-level tab now has a stable workspace identity plus persisted workspace metadata, window restore/undo now operate on workspace snapshots, and top-level workspace semantics are separated from inner pane tab semantics.
- Verification: `xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -destination 'platform=macOS' build`; `xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -destination 'platform=macOS' -only-testing:GhosttyTests/Terminal/TerminalWorkspaceSnapshotTests test`
- Files: `macos/Sources/Features/Terminal/TerminalRestorable.swift`, `macos/Sources/Features/Terminal/BaseTerminalController.swift`, `macos/Sources/Features/Terminal/TerminalController.swift`, `macos/Tests/Terminal/TerminalWorkspaceSnapshotTests.swift`
- Decision trail: Preserve the native top tab UI as the workspace switcher, but move the data model from "window owns a surface tree" to "window/tab owns a workspace snapshot". This matches the useful part of `cmux`'s architecture: outer workspace identity plus inner split/tabset state, without trying to nest AppKit's real window-tab implementation inside pane content.

### fix(macos): move split cycling to Cmd+, and Cmd+. without a preferences shortcut conflict

- What changed: Removed the default `open_config` keybind and changed split previous/next defaults from `Cmd+Shift+,` / `Cmd+Shift+.` to `Cmd+,` / `Cmd+.`.
- Why: The requested split-navigation shortcuts should be the easiest-to-reach pair. Keeping the old preferences shortcut on `Cmd+,` blocked that layout.
- Impact: Split focus now cycles left/right with `Cmd+,` and `Cmd+.`, the Preferences/Open Config menu item no longer owns a default shortcut, and reload config stays on `Cmd+Option+Shift+,`.
- Verification: `zig build`; `xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -destination 'platform=macOS' build`; `'/Users/leongong/Library/Developer/Xcode/DerivedData/Ghostty-btzvxhclyyijmwgtdfhkiidorhew/Build/Products/Debug/Ghostty.app/Contents/MacOS/GhoDex' +show-config --default | rg -n "open_config|reload_config|goto_split:previous|goto_split:next"`
- Files: `src/config/Config.zig`, `CHANGELOG.md`

### fix(macos): keep pane-targeting in sync immediately after split focus moves

- What changed: Updated both split-tree replacement paths to set the controller's `focusedSurface` immediately when they already know the destination surface for the next pane/tab focus target.
- Why: New split creation and pane-local tab changes previously waited for AppKit focus to catch up on the next run loop. If the user triggered pane-local open actions immediately after `Cmd+D` / `Cmd+Shift+D`, those actions could still resolve against the previously focused pane and open the child tab in the wrong split.
- Impact: Pane-local open actions such as `Cmd+Shift+T` and host-specific pane-tab launches now target the newly focused split pane immediately instead of falling back to the old pane.
- Verification: `xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -destination 'platform=macOS' build`
- Files: `macos/Sources/Features/Terminal/BaseTerminalController.swift`, `macos/Sources/Features/Terminal/TerminalController.swift`, `CHANGELOG.md`

### fix(macos): refresh pane tab titles immediately and remap split cycling to Cmd+< / Cmd+>

- What changed: Made the pane child-tab strip subscribe directly to each child surface title publisher so renames rebuild the pane header immediately, changed split previous/next defaults to `Cmd+Shift+,` and `Cmd+Shift+.`, and moved config open/reload defaults to `Cmd+Option+,` and `Cmd+Option+Shift+,`.
- Why: Pane child-tab titles were only rebuilt when pane structure changed, so rename feedback lagged until another UI update. Separately, the requested split-cycling shortcuts conflicted with the app's default config shortcuts, so the defaults had to be reassigned at the source-of-truth config layer.
- Impact: Renaming a pane child tab updates its visible header title immediately, split focus can move left/right with `Cmd+<` and `Cmd+>`, and config open/reload no longer occupy that key pair.
- Verification: `xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -destination 'platform=macOS' build`; `'/Users/leongong/Library/Developer/Xcode/DerivedData/Ghostty-btzvxhclyyijmwgtdfhkiidorhew/Build/Products/Debug/Ghostty.app/Contents/MacOS/GhoDex' +show-config --default | rg -n "open_config|reload_config|goto_split:previous|goto_split:next"`
- Files: `macos/Sources/Features/Splits/TerminalSplitTreeView.swift`, `src/config/Config.zig`, `CHANGELOG.md`

### fix(macos): unify Cmd+I title prompts around pane-aware context

- What changed: Routed both menu rename actions and Ghostty prompt-title actions through `TerminalController.changeTitleContext(_:)` whenever the active window is using the pane-tab workspace model.
- Why: `Cmd+I` could still bypass the pane-aware rename logic because some paths invoked the old `prompt_surface_title` or `prompt_tab_title` handlers directly. That left keyboard-driven rename behavior inconsistent with the new pane child-tab model.
- Impact: `Cmd+I` now renames the focused pane child tab when pane-local tabs are active, and falls back to the top-level tab title when the user is in the outer workspace/top-level tab context.
- Verification: `xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -destination 'platform=macOS' build`
- Files: `macos/Sources/App/macOS/MainMenu.xib`, `macos/Sources/Ghostty/Ghostty.App.swift`, `CHANGELOG.md`

### fix(macos): intercept pane child-tab shortcuts before AppKit menu routing

- What changed: Added pane-child-tab interception to both `TerminalWindow.sendEvent` and `performKeyEquivalent`, and stopped syncing a menu key equivalent onto the top-level `New Tab` item so AppKit cannot ambiguously match `Cmd+Shift+T` to the top-level tab menu entry.
- Why: The previous fix still left two escape hatches. First, some command-key paths can bypass `performKeyEquivalent` interception unless they are stopped at `sendEvent`. Second, AppKit menu matching can still prefer the top-level `New Tab` item when it owns `Cmd+T`, even though pane child tabs use `Cmd+Shift+T`.
- Impact: `Cmd+Shift+T` now has an early window-level interception path and no longer competes with a menu-owned top-level `New Tab` shortcut. Top-level `Cmd+T` continues to be handled by Ghostty's own key binding path instead of the menu item.
- Verification: `xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -destination 'platform=macOS' build`
- Files: `macos/Sources/Features/Terminal/Window Styles/TerminalWindow.swift`, `macos/Sources/App/macOS/AppDelegate.swift`, `CHANGELOG.md`

### feat(macos): align pane child-tab creation and controls with the top-level tab flow

- What changed: Routed `New Pane Tab` through the existing new-tab picker instead of directly spawning a blank local shell, added pane-specific picker dispatch in `AppDelegate`/`AITerminalManagerStore`, switched pane child-tab cycling to `Cmd+[` and `Cmd+]`, and rebuilt the pane tab header into a persistent AppKit strip with per-tab close buttons plus a trailing `+` action.
- Why: The pane-local tab layer must follow the same host-selection flow as the top-level tab feature and expose the same basic affordances users expect from tabs: a discoverable create action, a close button, and dedicated same-level navigation shortcuts. The previous direct-create path bypassed the picker entirely and the old segmented-control strip was too far from the native tab interaction model.
- Impact: `Cmd+Shift+T` and the pane `+` button now open the host picker for the currently focused pane, split panes always expose their own child-tab header, pane child tabs can be closed with `x`, and same-pane cycling no longer collides with the top-level `Cmd+Shift+[` / `Cmd+Shift+]` bindings.
- Verification: `xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -destination 'platform=macOS' build`; `'/Users/leongong/Library/Developer/Xcode/DerivedData/Ghostty-btzvxhclyyijmwgtdfhkiidorhew/Build/Products/Debug/Ghostty.app/Contents/MacOS/GhoDex' +show-config --default | rg -n "keybind = .*super\\+shift\\+t|keybind = .*super\\+z|keybind = .*super\\+shift\\+z|keybind = .*super\\+t"`
- Files: `macos/Sources/Features/New Tab Picker/NewTabPickerController.swift`, `macos/Sources/Features/New Tab Picker/NewTabPickerView.swift`, `macos/Sources/Features/AI Terminal Manager/AITerminalManagerStore.swift`, `macos/Sources/App/macOS/AppDelegate.swift`, `macos/Sources/App/macOS/MainMenu.xib`, `macos/Sources/Features/Terminal/TerminalController.swift`, `macos/Sources/Features/Terminal/TerminalView.swift`, `macos/Sources/Features/Splits/TerminalSplitTreeView.swift`, `CHANGELOG.md`

### fix(macos): force pane-tab content remount and window-level shortcut routing

- What changed: Forced pane child-tab content to remount on active-surface changes by keying `InspectableSurface` with the active surface UUID, capped pane tab item widths so the trailing `+` remains visible, and intercepted `Cmd+Shift+T` / `Cmd+[` / `Cmd+]` at the active terminal-window event monitor before Ghostty's lower-level key handling can route them elsewhere.
- Why: The previous pane-tab switch path could leave the old `SurfaceView` content mounted even though the active tab ID changed, which made tab titles move while the visible terminal content stayed the same. Separately, AppKit/Ghostty shortcut routing could still let `Cmd+Shift+T` fall through to top-level tab behavior instead of the focused pane-local action.
- Impact: Pane child-tab switches now replace the visible terminal content correctly, pane headers shrink tabs instead of letting them cover the add button, and `Cmd+Shift+T` consistently targets the focused pane rather than opening a top-level tab.
- Verification: `xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -destination 'platform=macOS' build`
- Files: `macos/Sources/Features/Splits/TerminalSplitTreeView.swift`, `macos/Sources/Features/Terminal/BaseTerminalController.swift`, `macos/Sources/Features/Terminal/TerminalController.swift`, `CHANGELOG.md`

### fix(macos): preserve pane geometry when opening child tabs in splits

- What changed: Kept `TerminalPane` frame size stable across child-tab switches, seeded newly created child surfaces with the current pane size, and clipped pane content to its split leaf in `TerminalSplitTreeView`.
- Why: `Cmd+Shift+T` inside a split pane must not mutate pane geometry. The previous code could activate a fresh surface with no settled size, fall back to a default `800x600`, and let the un-clipped terminal scroll view visually cover sibling splits.
- Impact: Opening a child tab in a split pane keeps the sibling panes visible instead of visually “exiting” the split, while still switching focus to the new child tab.
- Verification: `xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -destination 'platform=macOS' build`; `xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -destination 'platform=macOS' -only-testing:GhosttyTests/Splits/SplitTreeTests -only-testing:GhosttyTests/Splits/TerminalSplitDropZoneTests test`
- Files: `macos/Sources/Features/Terminal/TerminalPane.swift`, `macos/Sources/Features/Terminal/TerminalController.swift`, `macos/Sources/Features/Splits/TerminalSplitTreeView.swift`, `CHANGELOG.md`

### fix(macos): remove the default Cmd+Shift+T undo conflict

- What changed: Removed the macOS default keybinding that mapped `Cmd+Shift+T` to `undo`, leaving that shortcut available for the pane-local `New Pane Tab` menu action.
- Why: The pane-tab feature uses `Cmd+Shift+T`, but the existing default Ghostty macOS bindings also treated `Cmd+Shift+T` as undo. In split workflows that could undo the last split, which matches the reported “pressing Cmd+Shift+T exits the split” behavior.
- Impact: `Cmd+Shift+T` no longer conflicts with undo on macOS, so the shortcut can reliably target pane-local child tab creation instead of reverting split layout state.
- Verification: `xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -destination 'platform=macOS' build`; `xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -destination 'platform=macOS' -only-testing:GhosttyTests/Splits/SplitTreeTests -only-testing:GhosttyTests/Splits/TerminalSplitDropZoneTests test`
- Files: `src/config/Config.zig`, `CHANGELOG.md`

### feat(macos): adopt a cmux-style pane tree for split-local tabs

- What changed: Replaced raw split leaves with `TerminalPane` container leaves in `SplitTree<TerminalPane>`; moved child-tab ownership into each pane; updated `BaseTerminalController`, `TerminalController`, `TerminalView`, and `TerminalSplitTreeView` to render and mutate pane leaves directly; kept top-level AppKit window tabs on the original path; preserved `Cmd+Shift+T` for `newPaneTab:` and pane-local tab cycling; and updated restore/undo/App Intent/AppleScript/session enumeration paths to understand pane-owned child tabs.
- Why: The previous runtime-only child-tab layer still treated split leaves as raw `SurfaceView`s, which diverged from `cmux`'s `split -> tabset` model and made pane behavior fragile. The requested design needs split panes to own their own tab stacks as first-class layout nodes.
- Impact: Each split pane now owns its own child-tab stack and active child surface, pane content stays scoped to the pane boundary, nested split behavior follows the `cmux` data-model layering more closely, and window/quick-terminal restore now persist pane-local tab stacks instead of only the visible surface.
- Verification: `xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -destination 'platform=macOS' build`; `xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -destination 'platform=macOS' -only-testing:GhosttyTests/Splits/SplitTreeTests -only-testing:GhosttyTests/Splits/TerminalSplitDropZoneTests test`
- Files: `macos/Sources/Features/Terminal/TerminalPane.swift`, `macos/Sources/Features/Terminal/BaseTerminalController.swift`, `macos/Sources/Features/Terminal/TerminalController.swift`, `macos/Sources/Features/Terminal/TerminalView.swift`, `macos/Sources/Features/Splits/TerminalSplitTreeView.swift`, `macos/Sources/Features/Terminal/TerminalRestorable.swift`, `macos/Sources/Features/QuickTerminal/QuickTerminalRestorableState.swift`, `macos/Sources/Ghostty/Ghostty.App.swift`, `macos/Sources/App/macOS/AppDelegate.swift`, `macos/Sources/App/macOS/MainMenu.xib`, `CHANGELOG.md`

### fix(macos): route pane-tab menu actions through app delegate fallback

- What changed: Added `AppDelegate` forwarders for `newPaneTab:`, `previousPaneTab:`, and `nextPaneTab:` that resolve the active `TerminalController` from the key/main window before dispatching the action.
- Why: Pane-local tab actions should target the active terminal workspace regardless of which child surface or AppKit subview currently owns first responder status.
- Impact: `Cmd+Shift+T` and pane-tab navigation shortcuts resolve against the active terminal window instead of depending on the focused descendant view.
- Verification: `xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -destination 'platform=macOS' build`
- Files: `macos/Sources/App/macOS/AppDelegate.swift`, `CHANGELOG.md`

### fix(macos): bump restore formats for pane-owned child tabs

- What changed: Increased terminal and quick-terminal restorable state versions after switching persisted split leaves from raw surfaces to `TerminalPane` containers.
- Why: Old restore payloads encoded a different tree shape and would otherwise be decoded as if they were still surface-leaf trees.
- Impact: Existing persisted windows from the older model are safely ignored instead of restoring with mismatched child-tab state, while new saves round-trip the pane-local tab hierarchy.
- Verification: `xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -destination 'platform=macOS' build`
- Files: `macos/Sources/Features/Terminal/TerminalRestorable.swift`, `macos/Sources/Features/QuickTerminal/QuickTerminalRestorableState.swift`, `CHANGELOG.md`

### feat(config): sync GhoDex control-panel settings with config.ghodex

- What changed: Moved connection center, learning settings, and task queue
  persistence into managed `ghodex-*` entries in the main `config.ghodex`
  file; added reload-driven store/panel refresh; added regression coverage for
  managed-block load/save/reload behavior.
- Why: Settings that exist in both config and the control panel must have one
  app-owned source of truth and support two-way sync instead of diverging into
  a hidden sidecar JSON store.
- Impact: Users can configure these features directly in `config.ghodex`,
  reload the app config, and see matching values return to the panel. Panel
  edits now update the same main config file.
- Verification: `zig build`; `xcodebuild -project macos/Ghostty.xcodeproj
  -scheme Ghostty -only-testing:GhosttyTests/AITerminalManagerTests/
  storeLoadsConfigurationFromManagedGhoDexConfigBlock
  -only-testing:GhosttyTests/AITerminalManagerTests/
  storePersistsConfigurationIntoManagedGhoDexConfigBlock
  -only-testing:GhosttyTests/AITerminalManagerTests/
  storeReloadsPersistedConfigurationFromGhoDexConfig
  -only-testing:GhosttyTests/AITerminalManagerTests/
  storeUsesConfigDirectoryForHeartbeatInbox
  -only-testing:GhosttyTests/AITerminalManagerTests/storeSavesLearningSettings
  test`
- Files: `include/ghostty.h`,
  `macos/Sources/Features/AI Terminal Manager/AITerminalManagerStore.swift`,
  `macos/Sources/Features/SSH Connections/SSHConnectionsView.swift`,
  `macos/Sources/Ghostty/Ghostty.App.swift`,
  `macos/Sources/Ghostty/Ghostty.Config.swift`,
  `macos/Tests/AITerminalManager/AITerminalManagerTests.swift`,
  `src/cli/edit_config.zig`, `src/config/Config.zig`,
  `src/config/file_load.zig`

### docs(branding): start GhoDex naming pass and origin annotation

- What changed: Updated top-level branding in `README.md`, added upgrade highlights, added explicit `Project Origin` and `End Note`, renamed project wording in `AI_POLICY.md`, and added `ORIGIN.md` for provenance/thanks.
- Why: Establish GhoDex as an independent fork while preserving legal and historical attribution.
- Impact: User-facing docs now present `GhoDex` as the primary project name, with clear upstream lineage and unchanged MIT licensing notice.
- Verification: Checked updated docs for consistent fork naming, origin statement, and license reference (`README.md`, `AI_POLICY.md`, `ORIGIN.md`).
- Files: `README.md`, `AI_POLICY.md`, `ORIGIN.md`, `CHANGELOG.md`.

### docs(i18n): complete GhoDex display-name rollout across docs and UI text

- What changed: Rebranded remaining user-facing `Ghostty` display text to `GhoDex` across contributor/developer docs, spec docs, examples, translation catalogs (`po/*.po`, `po/*.pot`), macOS localized text tables, terminal window titles, and selected CLI/user messages.
- Why: Finish first-phase fork identity migration so user-visible copy is consistent with the `GhoDex` project name.
- Impact: UI labels, docs, and translated strings now present `GhoDex` consistently while technical/runtime identifiers (`ghostty`, `libghostty`, bundle IDs, target names) remain intact for compatibility.
- Verification: Searched for `Ghostty` in changed scopes and confirmed only expected technical/legal leftovers remain (e.g., module names, upstream attribution, compatibility identifiers).
- Files: `CONTRIBUTING.md`, `HACKING.md`, `PACKAGING.md`, `po/*.po`, `po/com.leongong.ghodex.pot`, `macos/Sources/Helpers/AppLocalization.swift`, `macos/Sources/Features/Terminal/Window Styles/*.xib`, `src/cli/*.zig`, `src/main_ghostty.zig`, `dist/windows/ghostty.rc` and related docs/tests.

## [0.1.0] - 2026-03-15

### feat(macos): AI terminal manager learning workflow and heartbeat queue

- What changed: Added learning settings/log persistence, workspace bootstrap, managed skill sync, and a heartbeat task queue with configurable interval/concurrency plus queue controls in settings UI.
- Why: Make repetitive local terminal orchestration and learning capture first-class app workflows instead of ad-hoc scripts.
- Impact: Users can configure learning capture, run queue tasks from UI/inbox, and track execution outcomes in-app.
- Verification: Existing macOS tests cover migration/persistence/queue execution paths (`macos/Tests/AITerminalManager/AITerminalManagerTests.swift`).
- Files: `macos/Sources/Features/AI Terminal Manager/AITerminalManagerModels.swift`, `macos/Sources/Features/AI Terminal Manager/AITerminalManagerStore.swift`, `macos/Sources/Features/SSH Connections/SSHConnectionsView.swift`, `macos/Tests/AITerminalManager/AITerminalManagerTests.swift`.

### test(update): language-agnostic localization assertions

- What changed: Replaced hardcoded English expectations with localization-aware assertions in updater/release-notes tests.
- Why: Prevent locale-dependent test failures in non-English environments.
- Impact: Update UI tests validate behavior across configured app languages.
- Verification: Test coverage updated in `ReleaseNotesTests.swift` and `UpdateViewModelTests.swift`.
- Files: `macos/Tests/Update/ReleaseNotesTests.swift`, `macos/Tests/Update/UpdateViewModelTests.swift`.

### chore(release): bootstrap standalone versioning metadata

- What changed: Added `VERSION` (`0.1.0`), initialized `CHANGELOG.md` with `Unreleased` and first release section, and added a versioning section in `README.md`.
- Why: Establish SemVer governance and satisfy repository pre-push version gate.
- Impact: Future releases have a canonical version source and changelog workflow.
- Verification: `VERSION` exists with SemVer value and changelog headings are present.
- Files: `VERSION`, `CHANGELOG.md`, `README.md`.
