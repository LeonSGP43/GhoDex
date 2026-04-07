export interface GatewayPairingQrPayload {
    host: string;
    port: number;
    pairingCode: string;
    desktopId?: string;
    transportMode?: 'lan' | 'relay';
    publicEndpoint?: string;
}

export interface GatewayPairingExchangeAttempt {
    host: string;
    port: number;
    desktopId?: string;
    transportMode: 'lan' | 'relay';
    publicEndpoint?: string;
}

const EXPECTED_KIND = 'ghodex.gateway.pairing';

export function parseGatewayPairingQrPayload(rawPayload: string): GatewayPairingQrPayload {
    const trimmed = rawPayload.trim();
    if (!trimmed) {
        throw new Error('QR payload is empty');
    }

    if (trimmed.startsWith('{')) {
        return parseJsonPayload(trimmed);
    }

    return parseUrlPayload(trimmed);
}

function parseJsonPayload(rawPayload: string): GatewayPairingQrPayload {
    let parsed: unknown;
    try {
        parsed = JSON.parse(rawPayload);
    } catch (error) {
        throw new Error('QR payload is not valid JSON');
    }

    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
        throw new Error('QR payload is not an object');
    }

    const object = parsed as Record<string, unknown>;
    if (typeof object.kind !== 'string' || object.kind !== EXPECTED_KIND) {
        throw new Error('QR kind is not a GhoDex pairing payload');
    }

    const publicEndpoint = parsePublicEndpoint(object.public_endpoint);
    const transportMode = normalizeTransportMode(
        parseTransportMode(object.preferred_transport ?? object.transport_mode ?? object.transport),
        publicEndpoint,
    );

    return {
        host: requireNonBlank(object.host, 'QR host is missing'),
        port: requirePort(object.port),
        pairingCode: requireNonBlank(object.pairing_code, 'QR pairing code is missing'),
        desktopId: parseDesktopId(object.desktop_id),
        transportMode,
        publicEndpoint,
    };
}

function parseUrlPayload(rawPayload: string): GatewayPairingQrPayload {
    let url: URL;
    try {
        url = new URL(rawPayload);
    } catch (error) {
        throw new Error('QR payload is not a supported URL');
    }

    if (url.protocol !== 'ghodex:') {
        throw new Error('QR scheme is not supported');
    }

    const route = url.hostname || url.host;
    if (route !== 'pair' && route !== 'pairing') {
        throw new Error('QR route is not a pairing payload');
    }

    const publicEndpoint = parsePublicEndpoint(url.searchParams.get('public_endpoint'));
    const transportMode = normalizeTransportMode(
        parseTransportMode(
            url.searchParams.get('preferred_transport')
            ?? url.searchParams.get('transport_mode')
            ?? url.searchParams.get('transport'),
        ),
        publicEndpoint,
    );

    return {
        host: requireNonBlank(url.searchParams.get('host'), 'QR host is missing'),
        port: requirePort(url.searchParams.get('port')),
        pairingCode: requireNonBlank(url.searchParams.get('pairing_code'), 'QR pairing code is missing'),
        desktopId: parseDesktopId(url.searchParams.get('desktop_id')),
        transportMode,
        publicEndpoint,
    };
}

export function buildGatewayPairingExchangeAttempts(payload: GatewayPairingQrPayload): GatewayPairingExchangeAttempt[] {
    const lanAttempt: GatewayPairingExchangeAttempt = {
        host: payload.host,
        port: payload.port,
        desktopId: payload.desktopId,
        transportMode: 'lan',
        publicEndpoint: undefined,
    };

    if (!payload.publicEndpoint) {
        return [lanAttempt];
    }

    const relayAttempt: GatewayPairingExchangeAttempt = {
        host: payload.host,
        port: payload.port,
        desktopId: payload.desktopId,
        transportMode: 'relay',
        publicEndpoint: payload.publicEndpoint,
    };

    const preferRelay = payload.transportMode === 'relay' || payload.transportMode === undefined;
    return preferRelay ? [relayAttempt, lanAttempt] : [lanAttempt, relayAttempt];
}

function requireNonBlank(value: unknown, message: string): string {
    if (typeof value !== 'string') {
        throw new Error(message);
    }

    const trimmed = value.trim();
    if (!trimmed) {
        throw new Error(message);
    }
    return trimmed;
}

function requirePort(value: unknown): number {
    const port = typeof value === 'number'
        ? value
        : typeof value === 'string'
            ? Number.parseInt(value, 10)
            : NaN;

    if (!Number.isFinite(port) || port < 1 || port > 65535) {
        throw new Error('QR port is invalid');
    }

    return Math.trunc(port);
}

function parseTransportMode(value: unknown): 'lan' | 'relay' | undefined {
    if (typeof value !== 'string') {
        return undefined;
    }

    const normalized = value.trim().toLowerCase();
    if (normalized === 'relay') {
        return 'relay';
    }
    if (normalized === 'lan' || normalized === 'tcp') {
        return 'lan';
    }
    return undefined;
}

function parsePublicEndpoint(value: unknown): string | undefined {
    if (typeof value !== 'string') {
        return undefined;
    }
    const trimmed = value.trim();
    if (!trimmed || !trimmed.startsWith('wss://')) {
        return undefined;
    }

    try {
        const parsed = new URL(trimmed);
        if (parsed.protocol !== 'wss:') {
            return undefined;
        }
        return trimmed;
    } catch {
        return undefined;
    }
}

function parseDesktopId(value: unknown): string | undefined {
    if (typeof value !== 'string') {
        return undefined;
    }
    const trimmed = value.trim();
    return trimmed || undefined;
}

function normalizeTransportMode(
    transportMode: 'lan' | 'relay' | undefined,
    publicEndpoint: string | undefined,
): 'lan' | 'relay' | undefined {
    if (transportMode === 'relay' && !publicEndpoint) {
        return undefined;
    }
    if (transportMode) {
        return transportMode;
    }
    if (publicEndpoint) {
        return 'relay';
    }
    return undefined;
}
