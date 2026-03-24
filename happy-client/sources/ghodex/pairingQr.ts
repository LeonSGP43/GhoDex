export interface GatewayPairingQrPayload {
    host: string;
    port: number;
    pairingCode: string;
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

    return {
        host: requireNonBlank(object.host, 'QR host is missing'),
        port: requirePort(object.port),
        pairingCode: requireNonBlank(object.pairing_code, 'QR pairing code is missing'),
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

    return {
        host: requireNonBlank(url.searchParams.get('host'), 'QR host is missing'),
        port: requirePort(url.searchParams.get('port')),
        pairingCode: requireNonBlank(url.searchParams.get('pairing_code'), 'QR pairing code is missing'),
    };
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
