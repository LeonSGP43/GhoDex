import * as SecureStore from 'expo-secure-store';
import { Platform } from 'react-native';

const STORAGE_KEY = 'ghodex.gateway.session.v1';

export interface StoredSession {
    host: string;
    port: number;
    pairingCode: string;
    authToken: string;
    tokenId: string;
    scopes: string[];
    requestedScopes: string[];
}

const DEFAULT_SESSION: StoredSession = {
    host: '127.0.0.1',
    port: 19527,
    pairingCode: '',
    authToken: '',
    tokenId: '',
    scopes: [],
    requestedScopes: ['observe', 'mutate'],
};

function cloneDefaultSession(): StoredSession {
    return {
        ...DEFAULT_SESSION,
        scopes: [...DEFAULT_SESSION.scopes],
        requestedScopes: [...DEFAULT_SESSION.requestedScopes],
    };
}

function sanitizeStoredSession(value: unknown): StoredSession {
    if (!value || typeof value !== 'object') {
        return cloneDefaultSession();
    }

    const object = value as Record<string, unknown>;
    const host = typeof object.host === 'string' && object.host.trim() ? object.host.trim() : DEFAULT_SESSION.host;
    const port = typeof object.port === 'number' && Number.isFinite(object.port) && object.port > 0
        ? Math.min(Math.trunc(object.port), 65535)
        : DEFAULT_SESSION.port;

    return {
        host,
        port,
        pairingCode: typeof object.pairingCode === 'string' ? object.pairingCode : '',
        authToken: typeof object.authToken === 'string' ? object.authToken : '',
        tokenId: typeof object.tokenId === 'string' ? object.tokenId : '',
        scopes: Array.isArray(object.scopes) ? object.scopes.filter((item): item is string => typeof item === 'string') : [],
        requestedScopes: Array.isArray(object.requestedScopes)
            ? object.requestedScopes.filter((item): item is string => typeof item === 'string')
            : [...DEFAULT_SESSION.requestedScopes],
    };
}

async function getStoredValue(): Promise<string | null> {
    if (Platform.OS === 'web') {
        return localStorage.getItem(STORAGE_KEY);
    }
    return SecureStore.getItemAsync(STORAGE_KEY);
}

async function setStoredValue(value: string): Promise<void> {
    if (Platform.OS === 'web') {
        localStorage.setItem(STORAGE_KEY, value);
        return;
    }
    await SecureStore.setItemAsync(STORAGE_KEY, value);
}

export async function loadStoredSession(): Promise<StoredSession> {
    try {
        const stored = await getStoredValue();
        if (!stored) {
            return cloneDefaultSession();
        }
        return sanitizeStoredSession(JSON.parse(stored));
    } catch (error) {
        console.warn('Failed to load stored GhoDex session', error);
        return cloneDefaultSession();
    }
}

export async function saveStoredSession(session: StoredSession): Promise<void> {
    await setStoredValue(JSON.stringify(sanitizeStoredSession(session)));
}

export async function clearStoredSession(): Promise<void> {
    if (Platform.OS === 'web') {
        localStorage.removeItem(STORAGE_KEY);
        return;
    }
    await SecureStore.deleteItemAsync(STORAGE_KEY);
}
