import Foundation

enum GhoDexHostInstanceEnvironment {
    static let controlSocketKey = "GHODEX_CONTROL_SOCKET"
    static let instancePIDKey = "GHODEX_INSTANCE_PID"
    static let instanceBundleIDKey = "GHODEX_INSTANCE_BUNDLE_ID"
    static let instanceExecutableKey = "GHODEX_INSTANCE_EXECUTABLE"

    static func inject(
        into environment: inout [String: String],
        controlSocketPath: String,
        processID: Int32,
        bundleID: String?,
        executablePath: String?
    ) {
        environment[controlSocketKey] = controlSocketPath
        environment[instancePIDKey] = String(processID)

        if let normalizedBundleID = normalizedValue(bundleID) {
            environment[instanceBundleIDKey] = normalizedBundleID
        }

        if let normalizedExecutablePath = normalizedValue(executablePath) {
            environment[instanceExecutableKey] = normalizedExecutablePath
        }
    }

    private static func normalizedValue(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
