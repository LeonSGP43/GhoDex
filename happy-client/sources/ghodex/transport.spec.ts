import { describe, expect, it, vi } from 'vitest';

vi.mock('@/encryption/aes', () => ({
    encryptAESGCM: async (data: Uint8Array) => Uint8Array.from(Array.from(data).reverse()),
    decryptAESGCM: async (data: Uint8Array) => Uint8Array.from(Array.from(data).reverse()),
}));

import {
    decodeEncryptedGatewayEnvelope,
    encodeEncryptedGatewayRequest,
    resolveGatewaySocketUrl,
    usesEncryptedGatewayTransport,
} from './transport';

describe('ghodex transport', () => {
    const sharedSecret = 'MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY=';

    it('uses ws for lan transport', () => {
        expect(resolveGatewaySocketUrl({
            transportMode: 'lan',
            host: '192.168.1.5',
            port: 19527,
            publicEndpoint: '',
        })).toBe('ws://192.168.1.5:19527');
        expect(usesEncryptedGatewayTransport({
            transportMode: 'lan',
            publicEndpoint: '',
            transportSharedSecret: '',
        })).toBe(false);
    });

    it('uses public endpoint for relay transport', () => {
        expect(resolveGatewaySocketUrl({
            transportMode: 'relay',
            host: '192.168.1.5',
            port: 19527,
            publicEndpoint: 'wss://edge.example.test/gateway',
        })).toBe('wss://edge.example.test/gateway');
        expect(usesEncryptedGatewayTransport({
            transportMode: 'relay',
            publicEndpoint: 'wss://edge.example.test/gateway',
            transportSharedSecret: sharedSecret,
        })).toBe(true);
    });

    it('falls back to lan url when relay endpoint is missing', () => {
        expect(resolveGatewaySocketUrl({
            transportMode: 'relay',
            host: 'desktop.local',
            port: 19527,
            publicEndpoint: '',
        })).toBe('ws://desktop.local:19527');
        expect(usesEncryptedGatewayTransport({
            transportMode: 'relay',
            publicEndpoint: '',
            transportSharedSecret: sharedSecret,
        })).toBe(false);
    });

    it('round trips encrypted request payloads', async () => {
        const request = {
            request_id: 'req-1',
            command: 'snapshot',
            auth_token: 'token-1',
        };

        const encrypted = await encodeEncryptedGatewayRequest({
            request,
            authToken: 'token-1',
            transportSharedSecret: sharedSecret,
        });

        expect(encrypted.command).toBe('gateway.encrypted');
        expect(encrypted.transport_mode).toBe('relay');
        expect(encrypted.auth_token).toBe('token-1');
        expect(encrypted.encrypted_payload.includes('snapshot')).toBe(false);

        const decoded = await decodeEncryptedGatewayEnvelope({
            encryptedEnvelope: {
                transport_mode: 'relay',
                encrypted_payload: encrypted.encrypted_payload,
            },
            transportSharedSecret: sharedSecret,
        });

        expect(decoded).toEqual(request);
    });
});
