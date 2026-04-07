import { describe, expect, it } from 'vitest';
import { applyGatewayConnectionSettings, applyPairingExchangeToSession, INITIAL_GATEWAY_SESSION } from './sessionState';

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

    it('lets a scanned QR endpoint override stale manual host and port', () => {
        const merged = applyGatewayConnectionSettings(
            {
                ...INITIAL_GATEWAY_SESSION,
                host: '192.168.3.145',
                port: 29527,
                authToken: 'token-scan',
            },
            {
                host: '192.168.3.100',
                port: 9527,
                liveUpdatesEnabled: false,
                pollIntervalMs: 1000,
            },
            {
                host: '192.168.3.145',
                port: 29527,
            },
        );

        expect(merged.host).toBe('192.168.3.145');
        expect(merged.port).toBe(29527);
        expect(merged.liveUpdatesEnabled).toBe(false);
        expect(merged.pollIntervalMs).toBe(1000);
        expect(merged.authToken).toBe('token-scan');
    });

    it('falls back to LAN when relay metadata has no desktop routing identity', () => {
        const merged = applyPairingExchangeToSession(
            {
                ...INITIAL_GATEWAY_SESSION,
                deviceId: 'device-4',
                desktopId: '',
                preferredDesktopId: '',
            },
            {
                host: '192.168.3.145',
                port: 29530,
                pairingCode: 'PAIR-MISSING-DESKTOP',
            },
            {
                authToken: 'token-missing-desktop',
                tokenId: 'token-id-missing-desktop',
                scopes: ['observe'],
                desktopId: null,
                desktopLabel: 'No desktop id',
                preferredDesktopId: null,
                transportMode: 'relay',
                publicEndpoint: 'wss://edge.example.test/gateway',
                transportSharedSecret: 'relay-secret',
            },
        );

        expect(merged.desktopId).toBe('');
        expect(merged.preferredDesktopId).toBe('');
        expect(merged.transportMode).toBe('lan');
        expect(merged.publicEndpoint).toBe('');
        expect(merged.transportSharedSecret).toBe('');
    });

    it('uses preferred desktop id as routing id when desktop_id is missing', () => {
        const merged = applyPairingExchangeToSession(
            {
                ...INITIAL_GATEWAY_SESSION,
                deviceId: 'device-5',
            },
            {
                host: '192.168.3.145',
                port: 29531,
                pairingCode: 'PAIR-PREFERRED-DESKTOP',
            },
            {
                authToken: 'token-preferred',
                tokenId: 'token-id-preferred',
                scopes: ['observe'],
                desktopId: null,
                desktopLabel: 'Preferred desktop',
                preferredDesktopId: 'desktop-preferred-only',
                transportMode: 'relay',
                publicEndpoint: 'wss://edge.example.test/gateway',
                transportSharedSecret: 'relay-secret',
            },
        );

        expect(merged.desktopId).toBe('desktop-preferred-only');
        expect(merged.preferredDesktopId).toBe('desktop-preferred-only');
        expect(merged.transportMode).toBe('relay');
        expect(merged.publicEndpoint).toBe('wss://edge.example.test/gateway');
        expect(merged.transportSharedSecret).toBe('relay-secret');
    });
});
