# Android Remote App Foundation

This directory now carries both the transport foundation and a real `android/app` shell for Milestone 4.

Current scope:

- packaged Java gateway request builders in `com.leongong.ghodex.remote`
- resume/subscription state for reconnect and replay
- a real TCP transport for the desktop gateway wire protocol
- JSON envelope decoding for gateway responses and event frames
- session store plus terminal index store, including snapshot terminal projection
- a UI-facing snapshot store driven by the client state machine
- a local client state machine that drives pairing, snapshot, subscribe, and mutation calls
- a minimal `android/app` Gradle module with a plain-Android transport UI and `SharedPreferences` persistence
- a local self-test that still compiles and runs with `javac` and `java`

Why Java first:

- this worktree currently has no Gradle wrapper
- this machine currently has `javac`, but not `gradle` or `kotlinc`
- a JDK-compiled contract layer was safer to verify first, and the app module now layers on top of that same package instead of replacing it

Current files:

- foundation:
  - `GhoDexGatewayRequest.java`
  - `GhoDexGatewayResumeState.java`
  - `GhoDexGatewayEnvelope.java`
  - `GhoDexGatewayTransport.java`
  - `GhoDexGatewayTcpTransport.java`
  - `GhoDexGatewayJsonCodec.java`
  - `GhoDexGatewaySessionStore.java`
  - `GhoDexTerminalIndexStore.java`
  - `GhoDexGatewayUiSnapshot.java`
  - `GhoDexGatewayUiStore.java`
  - `GhoDexGatewayClientStateMachine.java`
  - `GhoDexGatewayContractSelfTest.java`
- Android app shell:
  - `app/build.gradle.kts`
  - `app/src/main/AndroidManifest.xml`
  - `app/src/main/java/com/leongong/ghodex/androidapp/MainActivity.java`
  - `app/src/main/java/com/leongong/ghodex/androidapp/GatewayPreferencesStore.java`

Local verification:

```bash
tmpdir="$(mktemp -d)"
javac -d "$tmpdir" android/*.java
java -ea -cp "$tmpdir" com.leongong.ghodex.remote.GhoDexGatewayContractSelfTest
```

Next Milestone 4 steps:

- bind the same abstractions onto Android WebSocket transport when the desktop side opens that path
- run the `android/app` module on a device or emulator once a verified Android SDK + Gradle wrapper is available
- polish the app shell into a richer terminal index / session detail UI instead of the current single-screen text surface
