import { describe, expect, it } from 'vitest';
import { parseGatewayPairingQrPayload } from './pairingQr';

describe('ghodex pairing QR parser', () => {
    it('parses JSON pairing payloads', () => {
        expect(parseGatewayPairingQrPayload(JSON.stringify({
            kind: 'ghodex.gateway.pairing',
            host: '192.168.3.145',
            port: 29527,
            pairing_code: 'PAIR-JSON',
        }))).toEqual({
            host: '192.168.3.145',
            port: 29527,
            pairingCode: 'PAIR-JSON',
        });
    });

    it('parses ghodex URL pairing payloads', () => {
        expect(parseGatewayPairingQrPayload(
            'ghodex://pair?host=desktop.local&port=19527&pairing_code=PAIR-URL',
        )).toEqual({
            host: 'desktop.local',
            port: 19527,
            pairingCode: 'PAIR-URL',
        });
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
