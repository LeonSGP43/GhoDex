# Android Client Foundation

This directory starts Milestone 4 without assuming an existing Android app module.

Current scope:

- pure Java gateway request builders
- resume/subscription state for reconnect and replay
- transport and envelope abstractions
- session store plus terminal index store
- a local client state machine that drives pairing, snapshot, subscribe, and mutation calls
- a local self-test that compiles and runs with `javac` and `java`

Why Java first:

- this worktree currently has no Gradle wrapper
- this machine currently has `javac`, but not `gradle` or `kotlinc`
- a JDK-compiled contract layer is safer than adding an unverified Android shell

Current files:

- `GhoDexGatewayRequest.java`
- `GhoDexGatewayResumeState.java`
- `GhoDexGatewayEnvelope.java`
- `GhoDexGatewayTransport.java`
- `GhoDexGatewaySessionStore.java`
- `GhoDexTerminalIndexStore.java`
- `GhoDexGatewayClientStateMachine.java`
- `GhoDexGatewayContractSelfTest.java`

Local verification:

```bash
tmpdir="$(mktemp -d)"
javac -d "$tmpdir" android/*.java
java -ea -cp "$tmpdir" GhoDexGatewayContractSelfTest
```

Next Milestone 4 steps:

- bind this state machine onto a real socket/WebSocket transport
- persist session/index state into an actual Android app module
- promote this foundation into a Gradle/Kotlin Android module when toolchain support is available
