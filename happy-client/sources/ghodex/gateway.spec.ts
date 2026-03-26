import { afterEach, describe, expect, it, vi } from 'vitest';

vi.mock('@/encryption/aes', () => ({
    encryptAESGCM: async (data: Uint8Array) => data,
    decryptAESGCM: async (data: Uint8Array) => data,
}));

import { pairingBegin } from './gateway';

type MessageHandler = ((event: { data?: string }) => void) | null;
type EventHandler = (() => void) | null;

class MockWebSocket {
    static sentPayloads: Array<Record<string, unknown>> = [];

    onopen: EventHandler = null;
    onmessage: MessageHandler = null;
    onerror: EventHandler = null;
    onclose: ((event: { code: number; reason: string }) => void) | null = null;

    constructor(public readonly url: string) {
        queueMicrotask(() => {
            this.onopen?.();
        });
    }

    send(payload: string) {
        const parsed = JSON.parse(payload) as Record<string, unknown>;
        MockWebSocket.sentPayloads.push(parsed);
        queueMicrotask(() => {
            this.onmessage?.({
                data: JSON.stringify({
                    request_id: parsed.request_id,
                    status: 'ok',
                    result: {
                        pairing_code: 'PAIR-123',
                        client: parsed.client,
                        scopes: ['observe', 'mutate'],
                    },
                }),
            });
        });
    }

    close() {}
}

describe('ghodex gateway pairing', () => {
    const originalWebSocket = globalThis.WebSocket;

    afterEach(() => {
        MockWebSocket.sentPayloads = [];
        globalThis.WebSocket = originalWebSocket;
    });

    it('includes mobile device identity in pairing begin requests', async () => {
        globalThis.WebSocket = MockWebSocket as unknown as typeof WebSocket;

        await pairingBegin({
            host: '127.0.0.1',
            port: 19527,
            client: 'ghodex-remote-client',
            deviceId: 'device-alpha',
            deviceLabel: 'Alpha phone',
        });

        expect(MockWebSocket.sentPayloads).toHaveLength(1);
        expect(MockWebSocket.sentPayloads[0]).toMatchObject({
            command: 'gateway.pairing.begin',
            client: 'ghodex-remote-client',
            device_id: 'device-alpha',
            device_label: 'Alpha phone',
        });
    });
});
