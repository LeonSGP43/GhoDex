import Foundation

enum GhoDexHostInstanceEnvironment {
    static let controlSocketKey = "GHODEX_CONTROL_SOCKET"
    static let instancePIDKey = "GHODEX_INSTANCE_PID"
    static let instanceBundleIDKey = "GHODEX_INSTANCE_BUNDLE_ID"
    static let instanceExecutableKey = "GHODEX_INSTANCE_EXECUTABLE"
    static let runtimeSocketKey = "GHODEX_AGENT_RUNTIME_SOCKET"
    static let runtimeSessionKindKey = "GHODEX_AGENT_RUNTIME_SESSION_KIND"
    static let runtimeClientIDKey = "GHODEX_AGENT_RUNTIME_CLIENT_ID"
    static let runtimeWorkspaceIDKey = "GHODEX_AGENT_RUNTIME_WORKSPACE_ID"
    static let runtimeCapabilitiesKey = "GHODEX_AGENT_RUNTIME_CAPABILITIES"
    static let runtimeDefaultHeartbeatSecondsKey = "GHODEX_AGENT_RUNTIME_DEFAULT_HEARTBEAT_SECONDS"

    private static let aiManagerKey = "GHOSTTY_AI_MANAGER"
    private static let aiWorkspaceIDKey = "GHOSTTY_AI_WORKSPACE_ID"
    private static let aiManagerEnabledValue = "1"
    private static let defaultRuntimeCapabilities = [
        "runtime.executor.terminal",
        "runtime.executor.browser",
        "runtime.executor.vision",
        "runtime.observe",
        "runtime.task.claim",
        "runtime.task.manage",
    ]

    static func inject(
        into environment: inout [String: String],
        controlSocketPath: String,
        processID: Int32,
        bundleID: String?,
        executablePath: String?,
        runtimeDefaultHeartbeatSeconds: Double? = nil
    ) {
        environment[controlSocketKey] = controlSocketPath
        environment[instancePIDKey] = String(processID)

        if let normalizedBundleID = normalizedValue(bundleID) {
            environment[instanceBundleIDKey] = normalizedBundleID
        }

        if let normalizedExecutablePath = normalizedValue(executablePath) {
            environment[instanceExecutableKey] = normalizedExecutablePath
        }

        if let runtimeDefaultHeartbeatSeconds {
            injectManagedAgentRuntimeBootstrap(
                into: &environment,
                controlSocketPath: controlSocketPath,
                defaultHeartbeatSeconds: runtimeDefaultHeartbeatSeconds
            )
        }
    }

    private static func injectManagedAgentRuntimeBootstrap(
        into environment: inout [String: String],
        controlSocketPath: String,
        defaultHeartbeatSeconds: Double
    ) {
        guard normalizedValue(environment[aiManagerKey]) == aiManagerEnabledValue else {
            clearAgentRuntimeBootstrap(from: &environment)
            return
        }

        // V1 keeps runtime transport on the existing control harness socket.
        environment[runtimeSocketKey] = controlSocketPath
        environment[runtimeSessionKindKey] = AgentRuntimeClientKind.codexTab.rawValue
        environment[runtimeClientIDKey] = UUID().uuidString.lowercased()
        environment[runtimeCapabilitiesKey] = defaultRuntimeCapabilities.joined(separator: ",")
        environment[runtimeDefaultHeartbeatSecondsKey] = formattedSeconds(defaultHeartbeatSeconds)

        if let workspaceID = normalizedValue(environment[aiWorkspaceIDKey]) {
            environment[runtimeWorkspaceIDKey] = workspaceID
        } else {
            environment.removeValue(forKey: runtimeWorkspaceIDKey)
        }
    }

    private static func clearAgentRuntimeBootstrap(from environment: inout [String: String]) {
        environment.removeValue(forKey: runtimeSocketKey)
        environment.removeValue(forKey: runtimeSessionKindKey)
        environment.removeValue(forKey: runtimeClientIDKey)
        environment.removeValue(forKey: runtimeWorkspaceIDKey)
        environment.removeValue(forKey: runtimeCapabilitiesKey)
        environment.removeValue(forKey: runtimeDefaultHeartbeatSecondsKey)
    }

    private static func formattedSeconds(_ value: Double) -> String {
        let rounded = value.rounded()
        if abs(value - rounded) < 0.000_001 {
            return String(Int(rounded))
        }
        return String(value)
    }

    private static func normalizedValue(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
