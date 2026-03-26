import CryptoKit
import Foundation

struct ControlHarnessEncryptedGatewayRequest: Codable, Sendable {
    let requestID: String
    let command: String
    let authToken: String
    let transportMode: String
    let encryptedPayload: String

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case command
        case authToken = "auth_token"
        case transportMode = "transport_mode"
        case encryptedPayload = "encrypted_payload"
    }
}

struct ControlHarnessEncryptedGatewayEnvelope: Codable, Sendable {
    let transportMode: String
    let encryptedPayload: String

    enum CodingKeys: String, CodingKey {
        case transportMode = "transport_mode"
        case encryptedPayload = "encrypted_payload"
    }
}

enum ControlHarnessGatewaySecureChannelError: LocalizedError {
    case invalidSharedSecret
    case invalidEncryptedPayload
    case invalidEncryptedRequest

    var errorDescription: String? {
        switch self {
        case .invalidSharedSecret:
            return "The gateway transport shared secret is invalid"
        case .invalidEncryptedPayload:
            return "The encrypted gateway payload is invalid"
        case .invalidEncryptedRequest:
            return "The encrypted gateway request is invalid"
        }
    }
}

enum ControlHarnessGatewaySecureChannel {
    static func makeTransportSharedSecret() throws -> String {
        let bytes = Data((0..<32).map { _ in UInt8.random(in: UInt8.min...UInt8.max) })
        return bytes.base64EncodedString()
    }

    static func encryptRequest(
        _ request: ControlHarnessRequest,
        authToken: String,
        transportSharedSecret: String
    ) throws -> ControlHarnessEncryptedGatewayRequest {
        let payload = try JSONEncoder().encode(request)
        return ControlHarnessEncryptedGatewayRequest(
            requestID: request.requestID,
            command: "gateway.encrypted",
            authToken: authToken,
            transportMode: "relay",
            encryptedPayload: try encryptPayload(payload, transportSharedSecret: transportSharedSecret)
        )
    }

    static func decryptRequest(
        _ encryptedRequest: ControlHarnessEncryptedGatewayRequest,
        transportSharedSecret: String
    ) throws -> ControlHarnessRequest {
        guard encryptedRequest.command == "gateway.encrypted" else {
            throw ControlHarnessGatewaySecureChannelError.invalidEncryptedRequest
        }
        let payload = try decryptPayload(
            encryptedRequest.encryptedPayload,
            transportSharedSecret: transportSharedSecret
        )
        return try JSONDecoder().decode(ControlHarnessRequest.self, from: payload)
    }

    static func encryptEnvelope<T: Encodable>(
        _ value: T,
        transportSharedSecret: String
    ) throws -> ControlHarnessEncryptedGatewayEnvelope {
        let payload = try JSONEncoder().encode(value)
        return try encryptEnvelopeData(payload, transportSharedSecret: transportSharedSecret)
    }

    static func encryptEnvelopeData(
        _ payload: Data,
        transportSharedSecret: String
    ) throws -> ControlHarnessEncryptedGatewayEnvelope {
        ControlHarnessEncryptedGatewayEnvelope(
            transportMode: "relay",
            encryptedPayload: try encryptPayload(payload, transportSharedSecret: transportSharedSecret)
        )
    }

    static func decryptEnvelope<T: Decodable>(
        _ encryptedEnvelope: ControlHarnessEncryptedGatewayEnvelope,
        transportSharedSecret: String,
        as type: T.Type
    ) throws -> T {
        let payload = try decryptPayload(
            encryptedEnvelope.encryptedPayload,
            transportSharedSecret: transportSharedSecret
        )
        return try JSONDecoder().decode(type, from: payload)
    }

    static func decryptEnvelopeData(
        _ encryptedEnvelope: ControlHarnessEncryptedGatewayEnvelope,
        transportSharedSecret: String
    ) throws -> Data {
        try decryptPayload(
            encryptedEnvelope.encryptedPayload,
            transportSharedSecret: transportSharedSecret
        )
    }

    private static func encryptPayload(
        _ payload: Data,
        transportSharedSecret: String
    ) throws -> String {
        let key = try symmetricKey(from: transportSharedSecret)
        let sealedBox = try AES.GCM.seal(payload, using: key)
        guard let combined = sealedBox.combined else {
            throw ControlHarnessGatewaySecureChannelError.invalidEncryptedPayload
        }
        return encodeBase64URL(combined)
    }

    private static func decryptPayload(
        _ encryptedPayload: String,
        transportSharedSecret: String
    ) throws -> Data {
        let key = try symmetricKey(from: transportSharedSecret)
        let combined = try decodeBase64URL(encryptedPayload)
        let sealedBox = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(sealedBox, using: key)
    }

    private static func symmetricKey(from transportSharedSecret: String) throws -> SymmetricKey {
        guard let data = Data(base64Encoded: transportSharedSecret),
              data.isEmpty == false else {
            throw ControlHarnessGatewaySecureChannelError.invalidSharedSecret
        }
        return SymmetricKey(data: data)
    }

    private static func encodeBase64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func decodeBase64URL(_ value: String) throws -> Data {
        var normalized = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = normalized.count % 4
        if remainder != 0 {
            normalized += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: normalized) else {
            throw ControlHarnessGatewaySecureChannelError.invalidEncryptedPayload
        }
        return data
    }
}
