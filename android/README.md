# Android Client Foundation

This directory starts Milestone 4 without assuming an existing Android app module.

Current scope:

- pure Java gateway request builders
- resume/subscription state for reconnect and replay
- a local self-test that compiles and runs with `javac` and `java`

Why Java first:

- this worktree currently has no Gradle wrapper
- this machine currently has `javac`, but not `gradle` or `kotlinc`
- a JDK-compiled contract layer is safer than adding an unverified Android shell

Current files:

- `GhoDexGatewayRequest.java`
- `GhoDexGatewayResumeState.java`
- `GhoDexGatewayContractSelfTest.java`

Local verification:

```bash
tmpdir="$(mktemp -d)"
javac -d "$tmpdir" android/GhoDexGatewayRequest.java android/GhoDexGatewayResumeState.java android/GhoDexGatewayContractSelfTest.java
java -ea -cp "$tmpdir" GhoDexGatewayContractSelfTest
```

Next Milestone 4 steps:

- add a real transport adapter on top of this contract layer
- bind live gateway events into a terminal/session index store
- promote this foundation into a Gradle/Kotlin Android module when toolchain support is available
