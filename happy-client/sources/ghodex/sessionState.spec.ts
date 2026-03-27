import { describe, expect, it } from 'vitest';
import { applyPairingExchangeToSession, INITIAL_GATEWAY_SESSION } from './sessionState';

describe('ghodex session pairing merge', () => {
    it('clears stale relay metadata when a LAN pairing exchange completes', () => {
        const session = {
            ...INITIAL_GATEWAY_SESSION,
            deviceId: 'device-1',
            transportMode: 'relay' as const,
            publicEndpoint: 'wss://edge.example.test/gateway',
            transportSharedSecret: 'relay-secret',
            desktopId: 'desktop-old',
            desktopLabel: 'Old desktop',
            preferredDesktopId: 'desktop-old',
        };

        const merged = applyPairingExchangeToSession(
            session,
            {
                host: '192.168.3.145',
                port: 29527,
                pairingCode: 'PAIR-NEW',
            },
            {
                authToken: 'token-lan',
                tokenId: 'token-id-lan',
                scopes: ['observe', 'mutate'],
                desktopId: 'desktop-lan',
                desktopLabel: 'LAN desktop',
                preferredDesktopId: null,
                transportMode: 'lan',
                publicEndpoint: null,
                transportSharedSecret: null,
            },
        );

        expect(merged.host).toBe('192.168.3.145');
        expect(merged.port).toBe(29527);
        expect(merged.pairingCode).toBe('PAIR-NEW');
        expect(merged.transportMode).toBe('lan');
        expect(merged.publicEndpoint).toBe('');
        expect(merged.transportSharedSecret).toBe('');
        expect(merged.desktopId).toBe('desktop-lan');
        expect(merged.desktopLabel).toBe('LAN desktop');
        expect(merged.preferredDesktopId).toBe('desktop-lan');
    });

    it('keeps relay metadata only when the exchange response is complete', () => {
        const merged = applyPairingExchangeToSession(
            {
                ...INITIAL_GATEWAY_SESSION,
                deviceId: 'device-2',
            },
            {
                host: '192.168.3.145',
                port: 29528,
                pairingCode: 'PAIR-RELAY',
            },
            {
                authToken: 'token-relay',
                tokenId: 'token-id-relay',
                scopes: ['observe'],
                desktopId: 'desktop-relay',
                desktopLabel: 'Relay desktop',
                preferredDesktopId: 'desktop-relay-preferred',
                transportMode: 'relay',
                publicEndpoint: 'wss://edge.example.test/gateway',
                transportSharedSecret: 'relay-secret',
            },
        );

        expect(merged.transportMode).toBe('relay');
        expect(merged.publicEndpoint).toBe('wss://edge.example.test/gateway');
        expect(merged.transportSharedSecret).toBe('relay-secret');
        expect(merged.preferredDesktopId).toBe('desktop-relay-preferred');
    });

    it('falls back to LAN when relay metadata is incomplete', () => {
        const merged = applyPairingExchangeToSession(
            {
                ...INITIAL_GATEWAY_SESSION,
                deviceId: 'device-3',
                transportMode: 'relay',
                publicEndpoint: 'wss://stale.example.test/gateway',
                transportSharedSecret: 'stale-secret',
            },
            {
                host: '192.168.3.145',
                port: 29529,
                pairingCode: 'PAIR-INCOMPLETE',
            },
            {
                authToken: 'token-fallback',
                tokenId: 'token-id-fallback',
                scopes: ['observe'],
                desktopId: 'desktop-fallback',
                desktopLabel: 'Fallback desktop',
                preferredDesktopId: null,
                transportMode: 'relay',
                publicEndpoint: 'wss://edge.example.test/gateway',
                transportSharedSecret: null,
            },
        );

        expect(merged.transportMode).toBe('lan');
        expect(merged.publicEndpoint).toBe('');
        expect(merged.transportSharedSecret).toBe('');
    });
});
