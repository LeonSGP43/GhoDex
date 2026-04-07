import { decodeBase64, encodeBase64 } from '@/encryption/base64';
import { decryptAESGCM, encryptAESGCM } from '@/encryption/aes';

type GatewayTransportMode = 'lan' | 'relay';
type GatewayTransportModeInput = GatewayTransportMode | undefined;

interface GatewayTransportConfig {
    transportMode: GatewayTransportModeInput;
    host: string;
    port: number;
    desktopId?: string | null;
    publicEndpoint?: string | null;
    transportSharedSecret?: string | null;
}

interface GatewayTransportModeConfig {
    transportMode?: GatewayTransportMode;
    publicEndpoint?: string | null;
    transportSharedSecret?: string | null;
}

interface GatewayEncryptedTransportEnvelope {
    transport_mode?: string;
    encrypted_payload: string;
}

interface GatewayEncryptedRequestInput {
    request: Record<string, unknown>;
    authToken: string;
    transportSharedSecret: string;
}

export interface GatewayEncryptedRequest {
    request_id: string;
    command: 'gateway.encrypted';
    auth_token: string;
    transport_mode: 'relay';
    encrypted_payload: string;
}

function normalizePublicEndpoint(publicEndpoint?: string | null): string | null {
    const trimmed = publicEndpoint?.trim();
    if (!trimmed) {
        return null;
    }
    return trimmed.startsWith('wss://') ? trimmed : null;
}

function normalizeDesktopId(desktopId?: string | null): string | null {
    const trimmed = desktopId?.trim();
    return trimmed ? trimmed : null;
}

function encodeGatewayPayload(payload: Record<string, unknown>): Uint8Array {
    return new TextEncoder().encode(JSON.stringify(payload));
}

function decodeGatewayPayload(payload: Uint8Array): Record<string, unknown> {
    const parsed = JSON.parse(new TextDecoder().decode(payload));
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
        throw new Error('Encrypted gateway payload is not an object');
    }
    return parsed as Record<string, unknown>;
}

function buildLanSocketUrl(host: string, port: number): string {
    const trimmedHost = host.trim() || '127.0.0.1';
    const normalizedHost = trimmedHost.includes(':') && !trimmedHost.startsWith('[')
        ? `[${trimmedHost}]`
        : trimmedHost;
    return `ws://${normalizedHost}:${port}`;
}

function buildRelaySocketUrl(publicEndpoint: string, desktopId?: string | null): string {
    const routingDesktopID = normalizeDesktopId(desktopId);
    if (!routingDesktopID) {
        return publicEndpoint;
    }

    try {
        const endpoint = new URL(publicEndpoint);
        endpoint.searchParams.set('desktop_id', routingDesktopID);
        return endpoint.toString();
    } catch {
        return publicEndpoint;
    }
}

export function resolveGatewaySocketUrl(config: GatewayTransportConfig): string {
    const publicEndpoint = normalizePublicEndpoint(config.publicEndpoint);
    if (config.transportMode === 'relay' && publicEndpoint) {
        return buildRelaySocketUrl(publicEndpoint, config.desktopId);
    }
    return buildLanSocketUrl(config.host, config.port);
}

export function usesEncryptedGatewayTransport(config: GatewayTransportModeConfig): boolean {
    return config.transportMode === 'relay'
        && Boolean(normalizePublicEndpoint(config.publicEndpoint))
        && Boolean(config.transportSharedSecret?.trim());
}

export async function encodeEncryptedGatewayRequest(input: GatewayEncryptedRequestInput): Promise<GatewayEncryptedRequest> {
    const encrypted = await encryptAESGCM(
        encodeGatewayPayload(input.request),
        input.transportSharedSecret,
    );
    const requestID = typeof input.request.request_id === 'string' ? input.request.request_id : 'gateway-encrypted';
    return {
        request_id: requestID,
        command: 'gateway.encrypted',
        auth_token: input.authToken,
        transport_mode: 'relay',
        encrypted_payload: encodeBase64(encrypted, 'base64url'),
    };
}

export async function decodeEncryptedGatewayEnvelope(input: {
    encryptedEnvelope: GatewayEncryptedTransportEnvelope;
    transportSharedSecret: string;
}): Promise<Record<string, unknown>> {
    const encryptedPayload = input.encryptedEnvelope.encrypted_payload?.trim();
    if (!encryptedPayload) {
        throw new Error('Encrypted gateway envelope is missing encrypted_payload');
    }

    const decrypted = await decryptAESGCM(
        decodeBase64(encryptedPayload, 'base64url'),
        input.transportSharedSecret,
    );
    if (!decrypted) {
        throw new Error('Unable to decrypt gateway payload');
    }

    return decodeGatewayPayload(decrypted);
}
