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
- embedded camera-based QR pairing intake so the app can scan desktop-generated pairing payloads instead of relying on manual copy/paste or Play Services
- a checked-in Gradle wrapper so the app can be built on this machine without a global `gradle` install
- a local self-test that still compiles and runs with `javac` and `java`

Why Java first:

- this machine had `javac`, but not a global `gradle` or `kotlinc`
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
  - `gradlew`
  - `gradlew.bat`
  - `gradle/wrapper/gradle-wrapper.jar`
  - `gradle/wrapper/gradle-wrapper.properties`
  - `app/build.gradle.kts`
  - `app/src/main/AndroidManifest.xml`
  - `app/src/main/java/com/leongong/ghodex/androidapp/MainActivity.java`
  - `app/src/main/java/com/leongong/ghodex/androidapp/GatewayPreferencesStore.java`
  - `app/src/main/java/com/leongong/ghodex/androidapp/GatewayQrPayload.java`

Local verification:

```bash
tmpdir="$(mktemp -d)"
javac -d "$tmpdir" android/*.java
java -ea -cp "$tmpdir" com.leongong.ghodex.remote.GhoDexGatewayContractSelfTest
```

Build and install verification on this machine:

```bash
cd android
ANDROID_SDK_ROOT="$HOME/Library/Android/sdk" ./gradlew :app:assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell am start -n com.leongong.ghodex.androidapp/.MainActivity
```

QR pairing flow:

1. Launch the desktop app with the gateway enabled.
2. In the desktop app, open `Show Remote Pairing QR...`.
3. In Android, tap `Scan Pairing QR`.
4. The app will fill `host`, `port`, and `pairing code`, then immediately exchange and refresh snapshot.

Observed local environment:

- SDK root: `~/Library/Android/sdk`
- verified AVD: `Medium_Phone_API_35`
- verified package: `com.leongong.ghodex.androidapp`

Next Milestone 4 steps:

- bind the same abstractions onto Android WebSocket transport when the desktop side opens that path
- replace the current form-style control surface with a richer terminal index / active-terminal UI
- polish the app shell into a richer terminal index / session detail UI instead of the current single-screen text surface
