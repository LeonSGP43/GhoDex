import { afterEach, describe, expect, it, vi } from 'vitest';

vi.mock('@/encryption/aes', () => ({
    encryptAESGCM: async (data: Uint8Array) => data,
    decryptAESGCM: async (data: Uint8Array) => data,
}));

import { ackTerminalStream, subscribeToTerminalStream } from './gateway';

type MessageHandler = ((event: { data?: string }) => void) | null;
type EventHandler = (() => void) | null;

class MockWebSocket {
    static sentPayloads: Array<Record<string, unknown>> = [];
    static openedUrls: string[] = [];

    onopen: EventHandler = null;
    onmessage: MessageHandler = null;
    onerror: EventHandler = null;
    onclose: ((event: { code: number; reason: string }) => void) | null = null;

    constructor(public readonly url: string) {
        MockWebSocket.openedUrls.push(url);
        queueMicrotask(() => {
            this.onopen?.();
        });
    }

    send(payload: string) {
        const parsed = JSON.parse(payload) as Record<string, unknown>;
        MockWebSocket.sentPayloads.push(parsed);
        queueMicrotask(() => {
            if (parsed.command === 'terminal.stream.open') {
                this.onmessage?.({
                    data: JSON.stringify({
                        request_id: parsed.request_id,
                        status: 'ok',
                        result: {
                            protocol_version: '1.0',
                            stream_id: 'strm_abc',
                            terminal_id: parsed.terminal_id,
                            generation: 6,
                            mode: 'stream',
                            last_sequence: 98,
                            live_stream_open: true,
                            high_watermark_bytes: 1024,
                            low_watermark_bytes: 128,
                            unacked_bytes: 0,
                            flow_paused: false,
                        },
                    }),
                });
                this.onmessage?.({
                    data: JSON.stringify({
                        stream_kind: 'terminal_chunk',
                        stream_id: 'strm_abc',
                        terminal_id: parsed.terminal_id,
                        generation: 6,
                        frame_id: 'frm_2',
                        parent_frame_id: 'frm_1',
                        delta_kind: 'rows',
                        content: '[line 0] seed-line',
                        content_length: 18,
                        changed_rows: [
                            { index: 0, kind: 'update', text: 'seed-line' },
                        ],
                    }),
                });
                return;
            }

            if (parsed.command === 'terminal.stream.ack') {
                this.onmessage?.({
                    data: JSON.stringify({
                        request_id: parsed.request_id,
                        status: 'ok',
                        result: {
                            terminal_id: parsed.terminal_id,
                            stream_id: parsed.stream_id,
                            generation: 6,
                            acknowledged_bytes: parsed.ack_bytes,
                            remaining_unacked_bytes: 0,
                            high_watermark_bytes: 1024,
                            low_watermark_bytes: 128,
                            flow_paused: false,
                        },
                    }),
                });
            }
        });
    }

    close() {}
}

describe('gateway terminal stream APIs', () => {
    const originalWebSocket = globalThis.WebSocket;

    afterEach(() => {
        MockWebSocket.sentPayloads = [];
        MockWebSocket.openedUrls = [];
        globalThis.WebSocket = originalWebSocket;
    });

    it('sends terminal.stream.open and parses open ack + chunk payloads', async () => {
        globalThis.WebSocket = MockWebSocket as unknown as typeof WebSocket;

        const openPromise = new Promise<Record<string, unknown>>((resolve, reject) => {
            const unsubscribe = subscribeToTerminalStream({
                host: '127.0.0.1',
                port: 29527,
                authToken: 'TOKEN-123',
                terminalId: 'terminal-1',
                onOpen: (open) => resolve(open as unknown as Record<string, unknown>),
                onChunk: () => {},
                onError: (error) => reject(error),
            });
            setTimeout(() => {
                unsubscribe();
            }, 0);
        });

        const chunkPromise = new Promise<Record<string, unknown>>((resolve, reject) => {
            const unsubscribe = subscribeToTerminalStream({
                host: '127.0.0.1',
                port: 29527,
                authToken: 'TOKEN-123',
                terminalId: 'terminal-1',
                onOpen: () => {},
                onChunk: (chunk) => resolve(chunk as unknown as Record<string, unknown>),
                onError: (error) => reject(error),
            });
            setTimeout(() => {
                unsubscribe();
            }, 0);
        });

        await expect(openPromise).resolves.toMatchObject({
            streamId: 'strm_abc',
            terminalId: 'terminal-1',
            generation: 6,
            liveStreamOpen: true,
        });
        await expect(chunkPromise).resolves.toMatchObject({
            streamId: 'strm_abc',
            terminalId: 'terminal-1',
            frameId: 'frm_2',
            deltaKind: 'rows',
            content: '[line 0] seed-line',
            contentLength: 18,
            changedRows: [{ index: 0, kind: 'update', text: 'seed-line' }],
        });

        expect(MockWebSocket.sentPayloads[0]).toMatchObject({
            command: 'terminal.stream.open',
            auth_token: 'TOKEN-123',
            terminal_id: 'terminal-1',
            scope: 'visible',
        });
    });

    it('sends terminal.stream.ack and parses ack payload', async () => {
        globalThis.WebSocket = MockWebSocket as unknown as typeof WebSocket;

        await expect(ackTerminalStream({
            host: '127.0.0.1',
            port: 29527,
            authToken: 'TOKEN-123',
            terminalId: 'terminal-1',
            streamId: 'strm_abc',
            ackBytes: 512,
        })).resolves.toMatchObject({
            terminalId: 'terminal-1',
            streamId: 'strm_abc',
            generation: 6,
            acknowledgedBytes: 512,
            remainingUnackedBytes: 0,
            flowPaused: false,
        });

        expect(MockWebSocket.sentPayloads).toHaveLength(1);
        expect(MockWebSocket.sentPayloads[0]).toMatchObject({
            command: 'terminal.stream.ack',
            auth_token: 'TOKEN-123',
            terminal_id: 'terminal-1',
            stream_id: 'strm_abc',
            ack_bytes: 512,
        });
    });
});
