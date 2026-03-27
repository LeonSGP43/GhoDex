import { afterEach, describe, expect, it, vi } from 'vitest';

vi.mock('@/encryption/aes', () => ({
    encryptAESGCM: async (data: Uint8Array) => data,
    decryptAESGCM: async (data: Uint8Array) => data,
}));

import { pairingBegin, pairingExchange } from './gateway';

type MessageHandler = ((event: { data?: string }) => void) | null;
type EventHandler = (() => void) | null;

class MockWebSocket {
    static sentPayloads: Array<Record<string, unknown>> = [];
    static responseFactory: ((payload: Record<string, unknown>) => Record<string, unknown>) | null = null;
    static failOnOpen = false;

    onopen: EventHandler = null;
    onmessage: MessageHandler = null;
    onerror: EventHandler = null;
    onclose: ((event: { code: number; reason: string }) => void) | null = null;

    constructor(public readonly url: string) {
        queueMicrotask(() => {
            if (MockWebSocket.failOnOpen) {
                this.onerror?.();
                return;
            }
            this.onopen?.();
        });
    }

    send(payload: string) {
        const parsed = JSON.parse(payload) as Record<string, unknown>;
        MockWebSocket.sentPayloads.push(parsed);
        queueMicrotask(() => {
            const response = MockWebSocket.responseFactory
                ? MockWebSocket.responseFactory(parsed)
                : {
                    request_id: parsed.request_id,
                    status: 'ok',
                    result: {
                        pairing_code: 'PAIR-123',
                        client: parsed.client,
                        scopes: ['observe', 'mutate'],
                    },
                };
            this.onmessage?.({
                data: JSON.stringify(response),
            });
        });
    }

    close() {}
}

describe('ghodex gateway pairing', () => {
    const originalWebSocket = globalThis.WebSocket;

    afterEach(() => {
        MockWebSocket.sentPayloads = [];
        MockWebSocket.responseFactory = null;
        MockWebSocket.failOnOpen = false;
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

    it('maps pairing exchange responses into session metadata', async () => {
        globalThis.WebSocket = MockWebSocket as unknown as typeof WebSocket;
        MockWebSocket.responseFactory = (payload) => ({
            request_id: payload.request_id,
            status: 'ok',
            result: {
                token: 'token-1',
                token_id: 'token-id-1',
                scopes: ['observe'],
                desktop_id: 'desktop-1',
                desktop_label: 'Desk 1',
                preferred_desktop_id: 'desktop-preferred',
                transport_mode: 'relay',
                public_endpoint: 'wss://edge.example.test/gateway',
                transport_shared_secret: 'relay-secret',
            },
        });

        await expect(pairingExchange({
            host: '127.0.0.1',
            port: 19527,
            pairingCode: 'PAIR-123',
        })).resolves.toMatchObject({
            authToken: 'token-1',
            tokenId: 'token-id-1',
            desktopId: 'desktop-1',
            desktopLabel: 'Desk 1',
            preferredDesktopId: 'desktop-preferred',
            transportMode: 'relay',
            publicEndpoint: 'wss://edge.example.test/gateway',
            transportSharedSecret: 'relay-secret',
        });

        expect(MockWebSocket.sentPayloads[0]).toMatchObject({
            command: 'gateway.pairing.exchange',
            pairing_code: 'PAIR-123',
        });
    });

    it('surfaces websocket open failures with the failing url', async () => {
        globalThis.WebSocket = MockWebSocket as unknown as typeof WebSocket;
        MockWebSocket.failOnOpen = true;

        await expect(pairingExchange({
            host: '127.0.0.1',
            port: 19527,
            pairingCode: 'PAIR-123',
        })).rejects.toThrow('Unable to open WebSocket to ws://127.0.0.1:19527');
    });
});
