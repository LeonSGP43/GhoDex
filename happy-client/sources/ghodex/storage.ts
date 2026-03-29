import * as SecureStore from 'expo-secure-store';
import { randomUUID } from 'expo-crypto';
import { Platform } from 'react-native';
import { delay } from '@/utils/time';
import type { StoredSession, StoredTransportMode } from './sessionTypes';

const STORAGE_KEY = 'ghodex.gateway.session.v1';
const STORED_SESSION_TIMEOUT_MS = 1500;
const DEFAULT_DEVICE_LABEL = 'This phone';

const DEFAULT_DEVICE_ID = randomUUID();

const DEFAULT_SESSION: StoredSession = {
    deviceId: DEFAULT_DEVICE_ID,
    deviceLabel: DEFAULT_DEVICE_LABEL,
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
    requestedScopes: ['observe', 'mutate'],
    liveUpdatesEnabled: true,
    pollIntervalMs: 120,
};

function cloneDefaultSession(): StoredSession {
    return {
        ...DEFAULT_SESSION,
        scopes: [...DEFAULT_SESSION.scopes],
        requestedScopes: [...DEFAULT_SESSION.requestedScopes],
    };
}

function cloneStoredSession(session: StoredSession): StoredSession {
    return {
        ...session,
        scopes: [...session.scopes],
        requestedScopes: [...session.requestedScopes],
    };
}

let cachedSession: StoredSession | null = null;

function sanitizeTransportMode(value: unknown): StoredTransportMode {
    return value === 'relay' ? 'relay' : 'lan';
}

function sanitizeStoredSession(value: unknown): StoredSession {
    if (!value || typeof value !== 'object') {
        return cloneDefaultSession();
    }

    const object = value as Record<string, unknown>;
    const deviceId = typeof object.deviceId === 'string' && object.deviceId.trim()
        ? object.deviceId.trim()
        : DEFAULT_SESSION.deviceId;
    const desktopId = typeof object.desktopId === 'string' ? object.desktopId.trim() : '';
    const host = typeof object.host === 'string' && object.host.trim() ? object.host.trim() : DEFAULT_SESSION.host;
    const port = typeof object.port === 'number' && Number.isFinite(object.port) && object.port > 0
        ? Math.min(Math.trunc(object.port), 65535)
        : DEFAULT_SESSION.port;

    return {
        deviceId,
        deviceLabel: typeof object.deviceLabel === 'string' && object.deviceLabel.trim()
            ? object.deviceLabel.trim()
            : DEFAULT_SESSION.deviceLabel,
        desktopId,
        desktopLabel: typeof object.desktopLabel === 'string' ? object.desktopLabel.trim() : '',
        preferredDesktopId: typeof object.preferredDesktopId === 'string'
            ? object.preferredDesktopId.trim()
            : desktopId,
        transportMode: sanitizeTransportMode(object.transportMode),
        publicEndpoint: typeof object.publicEndpoint === 'string' ? object.publicEndpoint.trim() : '',
        transportSharedSecret: typeof object.transportSharedSecret === 'string'
            ? object.transportSharedSecret.trim()
            : '',
        host,
        port,
        pairingCode: typeof object.pairingCode === 'string' ? object.pairingCode : '',
        authToken: typeof object.authToken === 'string' ? object.authToken : '',
        tokenId: typeof object.tokenId === 'string' ? object.tokenId : '',
        scopes: Array.isArray(object.scopes) ? object.scopes.filter((item): item is string => typeof item === 'string') : [],
        requestedScopes: Array.isArray(object.requestedScopes)
            ? object.requestedScopes.filter((item): item is string => typeof item === 'string')
            : [...DEFAULT_SESSION.requestedScopes],
        liveUpdatesEnabled: object.liveUpdatesEnabled !== false,
        pollIntervalMs: typeof object.pollIntervalMs === 'number' && Number.isFinite(object.pollIntervalMs)
            ? Math.max(30, Math.min(Math.trunc(object.pollIntervalMs), 2000))
            : DEFAULT_SESSION.pollIntervalMs,
    };
}

async function getStoredValue(): Promise<string | null> {
    if (Platform.OS === 'web') {
        return localStorage.getItem(STORAGE_KEY);
    }
    return Promise.race([
        SecureStore.getItemAsync(STORAGE_KEY),
        delay(STORED_SESSION_TIMEOUT_MS).then(() => {
            console.warn(`Timed out loading stored GhoDex session after ${STORED_SESSION_TIMEOUT_MS}ms`);
            return null;
        }),
    ]);
}

async function setStoredValue(value: string): Promise<void> {
    if (Platform.OS === 'web') {
        localStorage.setItem(STORAGE_KEY, value);
        return;
    }
    await SecureStore.setItemAsync(STORAGE_KEY, value);
}

function clearStoredSessionBinding(session: StoredSession): StoredSession {
    return {
        ...session,
        desktopId: '',
        desktopLabel: '',
        preferredDesktopId: '',
        transportMode: 'lan',
        publicEndpoint: '',
        transportSharedSecret: '',
        pairingCode: '',
        authToken: '',
        tokenId: '',
        scopes: [],
    };
}

export function getCachedStoredSession(): StoredSession {
    return cachedSession ? cloneStoredSession(cachedSession) : cloneDefaultSession();
}

export async function loadStoredSession(): Promise<StoredSession> {
    if (cachedSession) {
        return cloneStoredSession(cachedSession);
    }

    try {
        const stored = await getStoredValue();
        const nextSession = stored ? sanitizeStoredSession(JSON.parse(stored)) : cloneDefaultSession();
        cachedSession = cloneStoredSession(nextSession);
        if (!stored) {
            await setStoredValue(JSON.stringify(nextSession));
        }
        return cloneStoredSession(nextSession);
    } catch (error) {
        console.warn('Failed to load stored GhoDex session', error);
        const nextSession = cloneDefaultSession();
        cachedSession = cloneStoredSession(nextSession);
        return nextSession;
    }
}

export async function saveStoredSession(session: StoredSession): Promise<void> {
    const sanitizedSession = sanitizeStoredSession(session);
    cachedSession = cloneStoredSession(sanitizedSession);
    await setStoredValue(JSON.stringify(sanitizedSession));
}

export async function clearStoredSession(): Promise<void> {
    const currentSession = cachedSession ? cloneStoredSession(cachedSession) : await loadStoredSession();
    const clearedSession = clearStoredSessionBinding(currentSession);
    cachedSession = cloneStoredSession(clearedSession);
    await setStoredValue(JSON.stringify(clearedSession));
}

export type { StoredSession, StoredTransportMode } from './sessionTypes';
