import { describe, expect, it } from 'vitest';
import { buildGatewayPairingExchangeAttempts, parseGatewayPairingQrPayload } from './pairingQr';

describe('ghodex pairing QR parser', () => {
    it('parses JSON pairing payloads', () => {
        expect(parseGatewayPairingQrPayload(JSON.stringify({
            kind: 'ghodex.gateway.pairing',
            host: '192.168.3.145',
            port: 29527,
            pairing_code: 'PAIR-JSON',
            desktop_id: 'desktop-json-1',
        }))).toEqual({
            host: '192.168.3.145',
            port: 29527,
            pairingCode: 'PAIR-JSON',
            desktopId: 'desktop-json-1',
        });
    });

    it('parses ghodex URL pairing payloads', () => {
        expect(parseGatewayPairingQrPayload(
            'ghodex://pair?host=desktop.local&port=19527&pairing_code=PAIR-URL&desktop_id=desktop-url-1',
        )).toEqual({
            host: 'desktop.local',
            port: 19527,
            pairingCode: 'PAIR-URL',
            desktopId: 'desktop-url-1',
        });
    });

    it('propagates desktop_id to relay and lan pairing attempts', () => {
        const attempts = buildGatewayPairingExchangeAttempts({
            host: 'desktop.local',
            port: 19527,
            pairingCode: 'PAIR-URL',
            desktopId: 'desktop-attempt-1',
            transportMode: 'relay',
            publicEndpoint: 'wss://edge.example.test/gateway',
        });

        expect(attempts).toEqual([
            {
                host: 'desktop.local',
                port: 19527,
                desktopId: 'desktop-attempt-1',
                transportMode: 'relay',
                publicEndpoint: 'wss://edge.example.test/gateway',
            },
            {
                host: 'desktop.local',
                port: 19527,
                desktopId: 'desktop-attempt-1',
                transportMode: 'lan',
                publicEndpoint: undefined,
            },
        ]);
    });

    it('rejects invalid QR payloads with stable messages', () => {
        expect(() => parseGatewayPairingQrPayload('')).toThrow('QR payload is empty');
        expect(() => parseGatewayPairingQrPayload('https://example.test')).toThrow('QR scheme is not supported');
        expect(() => parseGatewayPairingQrPayload('ghodex://other?host=x&port=1&pairing_code=y')).toThrow('QR route is not a pairing payload');
        expect(() => parseGatewayPairingQrPayload(JSON.stringify({
            kind: 'ghodex.gateway.pairing',
            host: '192.168.3.145',
            port: 0,
            pairing_code: 'PAIR-BAD',
        }))).toThrow('QR port is invalid');
        expect(() => parseGatewayPairingQrPayload(JSON.stringify({
            kind: 'wrong.kind',
            host: '192.168.3.145',
            port: 29527,
            pairing_code: 'PAIR-BAD',
        }))).toThrow('QR kind is not a GhoDex pairing payload');
    });
});
