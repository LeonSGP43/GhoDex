import { DEFAULT_REQUESTED_SCOPES } from './gateway';
import type { StoredSession } from './storage';

export const INITIAL_GATEWAY_SESSION: StoredSession = {
    host: '127.0.0.1',
    port: 19527,
    pairingCode: '',
    authToken: '',
    tokenId: '',
    scopes: [],
    requestedScopes: [...DEFAULT_REQUESTED_SCOPES],
};

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
