import { DEFAULT_REQUESTED_SCOPES } from './gateway';
import type { StoredSession } from './storage';

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
    requestedScopes: [...DEFAULT_REQUESTED_SCOPES],
    liveUpdatesEnabled: true,
    pollIntervalMs: 500,
};

export const POLL_INTERVAL_OPTIONS = [250, 500, 1000, 2000] as const;

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
