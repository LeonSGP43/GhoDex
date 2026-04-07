import type { StoredSession } from './sessionTypes';
import type { PairingExchangeResult } from './types';

const DEFAULT_GATEWAY_REQUESTED_SCOPES = ['observe', 'mutate'] as const;

export const INITIAL_GATEWAY_SESSION: StoredSession = {
    deviceId: '',
    deviceLabel: '',
    desktopId: '',
    desktopLabel: '',
    preferredDesktopId: '',
    transportMode: 'lan',
    publicEndpoint: '',
    transportSharedSecret: '',
    host: '127.0.0.1',
    port: 19527,
    pairingCode: '',
    authToken: '',
    tokenId: '',
    scopes: [],
    requestedScopes: [...DEFAULT_GATEWAY_REQUESTED_SCOPES],
    liveUpdatesEnabled: true,
    pollIntervalMs: 500,
};

export const POLL_INTERVAL_OPTIONS = [250, 500, 1000, 2000] as const;

export function applyGatewayConnectionSettings(
    base: StoredSession,
    input: {
        host: string;
        port: number;
        liveUpdatesEnabled: boolean;
        pollIntervalMs: number;
    },
    overrides?: Partial<StoredSession>,
): StoredSession {
    return {
        ...base,
        host: input.host,
        port: input.port,
        liveUpdatesEnabled: input.liveUpdatesEnabled,
        pollIntervalMs: input.pollIntervalMs,
        ...overrides,
    };
}

export function sanitizePort(raw: string | number): number {
    const normalized = typeof raw === 'number' ? String(raw) : raw;
    const digits = normalized.replace(/[^0-9]/g, '');
    if (!digits) {
        return INITIAL_GATEWAY_SESSION.port;
    }
    const next = Number.parseInt(digits, 10);
    if (!Number.isFinite(next) || next <= 0) {
        return INITIAL_GATEWAY_SESSION.port;
    }
    return Math.min(next, 65535);
}

export function sanitizePollInterval(raw: string | number): number {
    const normalized = typeof raw === 'number' ? raw : Number.parseInt(raw.replace(/[^0-9]/g, ''), 10);
    if (!Number.isFinite(normalized)) {
        return INITIAL_GATEWAY_SESSION.pollIntervalMs;
    }
    return Math.max(250, Math.min(Math.trunc(normalized), 2000));
}

export function applyPairingExchangeToSession(
    base: StoredSession,
    input: {
        host: string;
        port: number;
        pairingCode: string;
    },
    exchange: PairingExchangeResult,
): StoredSession {
    const normalizedPublicEndpoint = exchange.publicEndpoint?.trim() ?? '';
    const normalizedTransportSharedSecret = exchange.transportSharedSecret?.trim() ?? '';
    const normalizedDesktopID = exchange.desktopId?.trim()
        || exchange.preferredDesktopId?.trim()
        || base.desktopId.trim()
        || base.preferredDesktopId.trim()
        || '';
    const normalizedPreferredDesktopID = exchange.preferredDesktopId?.trim()
        || exchange.desktopId?.trim()
        || base.preferredDesktopId.trim()
        || base.desktopId.trim()
        || normalizedDesktopID;
    const relayRoutingDesktopID = normalizedDesktopID || normalizedPreferredDesktopID;
    const shouldUseRelay = exchange.transportMode === 'relay'
        && normalizedPublicEndpoint.length > 0
        && normalizedTransportSharedSecret.length > 0
        && relayRoutingDesktopID.length > 0;

    return {
        ...base,
        host: input.host,
        port: input.port,
        pairingCode: input.pairingCode,
        authToken: exchange.authToken,
        tokenId: exchange.tokenId ?? '',
        scopes: [...exchange.scopes],
        desktopId: relayRoutingDesktopID,
        desktopLabel: exchange.desktopLabel ?? base.desktopLabel,
        preferredDesktopId: normalizedPreferredDesktopID,
        transportMode: shouldUseRelay ? 'relay' : 'lan',
        publicEndpoint: shouldUseRelay ? normalizedPublicEndpoint : '',
        transportSharedSecret: shouldUseRelay ? normalizedTransportSharedSecret : '',
    };
}
