import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const secureStore = vi.hoisted(() => ({
    getItemAsync: vi.fn<() => Promise<string | null>>(),
    setItemAsync: vi.fn<() => Promise<void>>(),
}));

const crypto = vi.hoisted(() => ({
    randomUUID: vi.fn(() => 'device-test-id'),
}));

vi.mock('expo-secure-store', () => secureStore);
vi.mock('expo-crypto', () => crypto);
vi.mock('react-native', () => ({
    Platform: {
        OS: 'android',
    },
}));

describe('ghodex storage bootstrap safety', () => {
    beforeEach(() => {
        vi.resetModules();
        vi.clearAllMocks();
        vi.useFakeTimers();
    });

    afterEach(() => {
        vi.useRealTimers();
    });

    it('returns a session even if secure-store first write never resolves', async () => {
        secureStore.getItemAsync.mockImplementation(() => new Promise(() => {}));
        secureStore.setItemAsync.mockImplementation(() => new Promise(() => {}));

        const { loadStoredSession } = await import('./storage');
        const pending = loadStoredSession();

        await vi.advanceTimersByTimeAsync(1600);
        const session = await pending;

        expect(session.deviceId).toBe('device-test-id');
        expect(session.host).toBe('127.0.0.1');
        expect(secureStore.getItemAsync).toHaveBeenCalledTimes(1);
        expect(secureStore.setItemAsync).toHaveBeenCalledTimes(1);
    });
});

