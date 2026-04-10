import { afterEach, describe, expect, it, vi } from 'vitest';

vi.mock('@/encryption/aes', () => ({
    encryptAESGCM: async (data: Uint8Array) => data,
    decryptAESGCM: async (data: Uint8Array) => data,
}));

import { ackTerminalStream, createTerminalMutationChannel, subscribeToGatewayEvents, subscribeToTerminalStream } from './gateway';
import { decodeEncryptedGatewayEnvelope, encodeEncryptedGatewayRequest } from './transport';

type MessageHandler = ((event: { data?: string }) => void) | null;
type EventHandler = (() => void) | null;

class MockWebSocket {
    static sentPayloads: Array<Record<string, unknown>> = [];
    static openedUrls: string[] = [];
    static relaySharedSecret = 'relay-secret';
    static mutedCommands = new Set<string>();
    static mismatchRequestIDCommands = new Set<string>();
    static missingRequestIDCommands = new Set<string>();
    static closeBeforeReplyCommands = new Set<string>();
    static failOnOpen = false;
    static holdOpen = false;
    static eventStreamDrainCount = 0;

    onopen: EventHandler = null;
    onmessage: MessageHandler = null;
    onerror: EventHandler = null;
    onclose: ((event: { code: number; reason: string }) => void) | null = null;

    constructor(public readonly url: string) {
        MockWebSocket.openedUrls.push(url);
        if (MockWebSocket.holdOpen) {
            return;
        }
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
        const command = typeof parsed.command === 'string' ? parsed.command : '';

        queueMicrotask(() => {
            if (command === 'gateway.encrypted' && typeof parsed.encrypted_payload === 'string') {
                void decodeEncryptedGatewayEnvelope({
                    encryptedEnvelope: {
                        transport_mode: 'relay',
                        encrypted_payload: parsed.encrypted_payload,
                    },
                    transportSharedSecret: MockWebSocket.relaySharedSecret,
                }).then((decryptedPayload) => {
                    const decryptedCommand = typeof decryptedPayload.command === 'string' ? decryptedPayload.command : '';
                    if (MockWebSocket.closeBeforeReplyCommands.has(decryptedCommand)) {
                        this.onclose?.({
                            code: 1011,
                            reason: 'simulated close before reply',
                        });
                        return;
                    }

                    if (MockWebSocket.mutedCommands.has(decryptedCommand)) {
                        return;
                    }

                    if (decryptedCommand === 'send-text' || decryptedCommand === 'send-key') {
                        const terminalID = typeof decryptedPayload.terminal_id === 'string' ? decryptedPayload.terminal_id : '';
                        const originalRequestID = typeof decryptedPayload.request_id === 'string' ? decryptedPayload.request_id : 'unknown';
                        const missingRequestID = MockWebSocket.missingRequestIDCommands.has(decryptedCommand);
                        const requestID = MockWebSocket.mismatchRequestIDCommands.has(decryptedCommand)
                            ? `${originalRequestID}-mismatch`
                            : originalRequestID;
                        const response: Record<string, unknown> = {
                            status: 'ok',
                            result: {
                                terminal_id: terminalID,
                                generation: 7,
                                sequence: 123,
                                operation: decryptedCommand,
                                acknowledged: true,
                                write_id: 'wr_mutation',
                            },
                        };
                        if (!missingRequestID) {
                            response.request_id = requestID;
                        }
                        void encodeEncryptedGatewayRequest({
                            request: response,
                            authToken: typeof parsed.auth_token === 'string' ? parsed.auth_token : 'TOKEN-123',
                            transportSharedSecret: MockWebSocket.relaySharedSecret,
                        }).then((encryptedResponse) => {
                            this.onmessage?.({
                                data: JSON.stringify(encryptedResponse),
                            });
                        }).catch(() => {
                            this.onerror?.();
                        });
                    }
                }).catch(() => {
                    this.onerror?.();
                });
                return;
            }

            if (MockWebSocket.closeBeforeReplyCommands.has(command)) {
                this.onclose?.({
                    code: 1011,
                    reason: 'simulated close before reply',
                });
                return;
            }

            if (MockWebSocket.mutedCommands.has(command)) {
                return;
            }

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
                return;
            }

            if (parsed.command === 'events.stream.subscribe') {
                this.onmessage?.({
                    data: JSON.stringify({
                        request_id: parsed.request_id,
                        status: 'ok',
                        result: {
                            protocol_version: '1.0',
                            subscribed: true,
                            stream_id: 'evt_strm_1',
                            last_sequence: parsed.since_sequence ?? 0,
                            since_sequence: parsed.since_sequence ?? 0,
                            event_limit: parsed.event_limit ?? 128,
                            replayed_event_count: 0,
                            live_stream_open: true,
                        },
                    }),
                });
                return;
            }

            if (parsed.command === 'events.stream.drain') {
                MockWebSocket.eventStreamDrainCount += 1;
                const firstDrain = MockWebSocket.eventStreamDrainCount === 1;
                this.onmessage?.({
                    data: JSON.stringify({
                        request_id: parsed.request_id,
                        status: 'ok',
                        result: {
                            protocol_version: '1.0',
                            stream_id: parsed.stream_id,
                            last_sequence: firstDrain ? 105 : 105,
                            event_limit: 128,
                            drained_event_count: firstDrain ? 1 : 0,
                            requires_snapshot_resync: false,
                            dropped_events: 0,
                            live_stream_open: true,
                            events: firstDrain ? [{
                                event: 'terminal.input.sent',
                                sequence: 105,
                                resource: {
                                    type: 'terminal',
                                    id: 'terminal-1',
                                    generation: 7,
                                },
                                payload: {
                                    write_id: 'wr_123',
                                },
                            }] : [],
                        },
                    }),
                });
                return;
            }

            if (parsed.command === 'events.stream.unsubscribe') {
                this.onmessage?.({
                    data: JSON.stringify({
                        request_id: parsed.request_id,
                        status: 'ok',
                        result: {
                            protocol_version: '1.0',
                            stream_id: parsed.stream_id,
                            unsubscribed: true,
                        },
                    }),
                });
                return;
            }

            if (parsed.command === 'send-text' || parsed.command === 'send-key') {
                const missingRequestID = MockWebSocket.missingRequestIDCommands.has(command);
                const requestID = MockWebSocket.mismatchRequestIDCommands.has(command)
                    ? `${String(parsed.request_id ?? 'unknown')}-mismatch`
                    : parsed.request_id;
                const response: Record<string, unknown> = {
                    status: 'ok',
                    result: {
                        terminal_id: parsed.terminal_id,
                        generation: 7,
                        sequence: 123,
                        operation: parsed.command,
                        acknowledged: true,
                        write_id: 'wr_mutation',
                    },
                };
                if (!missingRequestID) {
                    response.request_id = requestID;
                }
                this.onmessage?.({
                    data: JSON.stringify(response),
                });
            }
        });
    }

    close() {
        queueMicrotask(() => {
            this.onclose?.({ code: 1000, reason: 'client closed' });
        });
    }
}

describe('gateway terminal stream APIs', () => {
    const originalWebSocket = globalThis.WebSocket;

    afterEach(() => {
        MockWebSocket.sentPayloads = [];
        MockWebSocket.openedUrls = [];
        MockWebSocket.mutedCommands.clear();
        MockWebSocket.mismatchRequestIDCommands.clear();
        MockWebSocket.missingRequestIDCommands.clear();
        MockWebSocket.closeBeforeReplyCommands.clear();
        MockWebSocket.failOnOpen = false;
        MockWebSocket.holdOpen = false;
        MockWebSocket.eventStreamDrainCount = 0;
        vi.useRealTimers();
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

    it('uses buffered events.stream flow for gateway events', async () => {
        globalThis.WebSocket = MockWebSocket as unknown as typeof WebSocket;

        const receivedEnvelopes: Array<Record<string, unknown>> = [];
        const unsubscribe = subscribeToGatewayEvents({
            host: '127.0.0.1',
            port: 29527,
            authToken: 'TOKEN-123',
            sinceSequence: 99,
            eventLimit: 64,
            onEnvelope: (envelope) => {
                receivedEnvelopes.push(envelope as unknown as Record<string, unknown>);
            },
        });

        await vi.waitFor(() => {
            expect(MockWebSocket.sentPayloads.map((payload) => payload.command)).toContain('events.stream.drain');
            expect(receivedEnvelopes).toEqual(expect.arrayContaining([
                expect.objectContaining({
                    request_id: expect.any(String),
                    status: 'ok',
                    result: expect.objectContaining({
                        stream_id: 'evt_strm_1',
                    }),
                }),
                expect.objectContaining({
                    event: 'terminal.input.sent',
                    sequence: 105,
                    resource: expect.objectContaining({
                        type: 'terminal',
                        id: 'terminal-1',
                    }),
                }),
            ]));
        });

        unsubscribe();

        await vi.waitFor(() => {
            expect(MockWebSocket.sentPayloads.map((payload) => payload.command)).toContain('events.stream.unsubscribe');
        });

        expect(MockWebSocket.sentPayloads[0]).toMatchObject({
            command: 'events.stream.subscribe',
            auth_token: 'TOKEN-123',
            since_sequence: 99,
            event_limit: 64,
        });
        expect(MockWebSocket.sentPayloads.map((payload) => payload.command)).toEqual(expect.arrayContaining([
            'events.stream.subscribe',
            'events.stream.drain',
            'events.stream.unsubscribe',
        ]));
    });

    it('reuses one websocket connection for sequential terminal mutations', async () => {
        globalThis.WebSocket = MockWebSocket as unknown as typeof WebSocket;
        const channel = createTerminalMutationChannel({
            host: '127.0.0.1',
            port: 29527,
        });

        await expect(channel.sendText({
            authToken: 'TOKEN-123',
            terminalId: 'terminal-1',
            text: 'echo hello',
        })).resolves.toMatchObject({
            terminalId: 'terminal-1',
            operation: 'send-text',
            acknowledged: true,
        });

        await expect(channel.sendKey({
            authToken: 'TOKEN-123',
            terminalId: 'terminal-1',
            terminalKey: 'enter',
        })).resolves.toMatchObject({
            terminalId: 'terminal-1',
            operation: 'send-key',
            acknowledged: true,
        });

        channel.close();

        expect(MockWebSocket.openedUrls).toHaveLength(1);
        expect(MockWebSocket.sentPayloads.map((payload) => payload.command)).toEqual(['send-text', 'send-key']);
    });

    it('rejects timed-out mutation requests and reconnects for subsequent sends', async () => {
        globalThis.WebSocket = MockWebSocket as unknown as typeof WebSocket;
        vi.useFakeTimers();
        MockWebSocket.mutedCommands.add('send-text');
        const channel = createTerminalMutationChannel({
            host: '127.0.0.1',
            port: 29527,
        });

        const timeoutPromise = channel.sendText({
            authToken: 'TOKEN-123',
            terminalId: 'terminal-1',
            text: 'echo timeout',
        });
        const timeoutExpectation = expect(timeoutPromise).rejects.toThrow('Gateway request timed out after 10000ms');

        await vi.advanceTimersByTimeAsync(10_001);
        await timeoutExpectation;

        MockWebSocket.mutedCommands.delete('send-text');
        await expect(channel.sendKey({
            authToken: 'TOKEN-123',
            terminalId: 'terminal-1',
            terminalKey: 'enter',
        })).resolves.toMatchObject({
            terminalId: 'terminal-1',
            operation: 'send-key',
            acknowledged: true,
        });

        channel.close();
        expect(MockWebSocket.openedUrls).toHaveLength(2);
    });

    it('rejects request_id mismatch replies and reconnects cleanly', async () => {
        globalThis.WebSocket = MockWebSocket as unknown as typeof WebSocket;
        MockWebSocket.mismatchRequestIDCommands.add('send-text');
        const channel = createTerminalMutationChannel({
            host: '127.0.0.1',
            port: 29527,
        });

        await expect(channel.sendText({
            authToken: 'TOKEN-123',
            terminalId: 'terminal-1',
            text: 'echo mismatch',
        })).rejects.toThrow('Gateway response request_id does not match active mutation request');

        MockWebSocket.mismatchRequestIDCommands.delete('send-text');
        await expect(channel.sendKey({
            authToken: 'TOKEN-123',
            terminalId: 'terminal-1',
            terminalKey: 'enter',
        })).resolves.toMatchObject({
            terminalId: 'terminal-1',
            operation: 'send-key',
            acknowledged: true,
        });

        channel.close();
        expect(MockWebSocket.openedUrls).toHaveLength(2);
    });

    it('rejects missing request_id replies and reconnects cleanly', async () => {
        globalThis.WebSocket = MockWebSocket as unknown as typeof WebSocket;
        MockWebSocket.missingRequestIDCommands.add('send-text');
        const channel = createTerminalMutationChannel({
            host: '127.0.0.1',
            port: 29527,
        });

        await expect(channel.sendText({
            authToken: 'TOKEN-123',
            terminalId: 'terminal-1',
            text: 'echo missing-id',
        })).rejects.toThrow('Gateway response request_id is missing for active mutation request');

        MockWebSocket.missingRequestIDCommands.delete('send-text');
        await expect(channel.sendKey({
            authToken: 'TOKEN-123',
            terminalId: 'terminal-1',
            terminalKey: 'enter',
        })).resolves.toMatchObject({
            terminalId: 'terminal-1',
            operation: 'send-key',
            acknowledged: true,
        });

        channel.close();
        expect(MockWebSocket.openedUrls).toHaveLength(2);
    });

    it('rejects missing request_id replies on encrypted relay transport and reconnects cleanly', async () => {
        globalThis.WebSocket = MockWebSocket as unknown as typeof WebSocket;
        MockWebSocket.missingRequestIDCommands.add('send-text');
        const channel = createTerminalMutationChannel({
            host: '127.0.0.1',
            port: 29527,
            desktopId: 'desktop-relay-stream-1',
            transportMode: 'relay',
            publicEndpoint: 'wss://edge.example.test/gateway',
            transportSharedSecret: MockWebSocket.relaySharedSecret,
        });

        await expect(channel.sendText({
            authToken: 'TOKEN-123',
            terminalId: 'terminal-1',
            text: 'echo missing-id-relay',
        })).rejects.toThrow('Gateway response request_id is missing for active mutation request');

        MockWebSocket.missingRequestIDCommands.delete('send-text');
        await expect(channel.sendKey({
            authToken: 'TOKEN-123',
            terminalId: 'terminal-1',
            terminalKey: 'enter',
        })).resolves.toMatchObject({
            terminalId: 'terminal-1',
            operation: 'send-key',
            acknowledged: true,
        });

        expect(MockWebSocket.openedUrls).toHaveLength(2);
        expect(MockWebSocket.openedUrls).toEqual([
            'wss://edge.example.test/gateway?desktop_id=desktop-relay-stream-1',
            'wss://edge.example.test/gateway?desktop_id=desktop-relay-stream-1',
        ]);
        expect(MockWebSocket.sentPayloads[0]?.command).toBe('gateway.encrypted');
        expect(MockWebSocket.sentPayloads[1]?.command).toBe('gateway.encrypted');

        const firstDecrypted = await decodeEncryptedGatewayEnvelope({
            encryptedEnvelope: {
                transport_mode: 'relay',
                encrypted_payload: String(MockWebSocket.sentPayloads[0]?.encrypted_payload ?? ''),
            },
            transportSharedSecret: MockWebSocket.relaySharedSecret,
        });
        expect(firstDecrypted.command).toBe('send-text');

        channel.close();
    });

    it('rejects socket close before reply and reconnects on next mutation', async () => {
        globalThis.WebSocket = MockWebSocket as unknown as typeof WebSocket;
        MockWebSocket.closeBeforeReplyCommands.add('send-text');
        const channel = createTerminalMutationChannel({
            host: '127.0.0.1',
            port: 29527,
        });

        await expect(channel.sendText({
            authToken: 'TOKEN-123',
            terminalId: 'terminal-1',
            text: 'echo close',
        })).rejects.toThrow('simulated close before reply');

        MockWebSocket.closeBeforeReplyCommands.delete('send-text');
        await expect(channel.sendKey({
            authToken: 'TOKEN-123',
            terminalId: 'terminal-1',
            terminalKey: 'enter',
        })).resolves.toMatchObject({
            terminalId: 'terminal-1',
            operation: 'send-key',
            acknowledged: true,
        });

        channel.close();
        expect(MockWebSocket.openedUrls).toHaveLength(2);
    });

    it('rejects in-flight mutation when channel is closed by client', async () => {
        globalThis.WebSocket = MockWebSocket as unknown as typeof WebSocket;
        MockWebSocket.mutedCommands.add('send-text');
        const channel = createTerminalMutationChannel({
            host: '127.0.0.1',
            port: 29527,
        });

        const inFlight = channel.sendText({
            authToken: 'TOKEN-123',
            terminalId: 'terminal-1',
            text: 'echo close-by-client',
        });
        for (let attempt = 0; attempt < 8 && MockWebSocket.sentPayloads.length === 0; attempt += 1) {
            await Promise.resolve();
        }
        expect(MockWebSocket.sentPayloads.length).toBeGreaterThan(0);
        channel.close();

        await expect(inFlight).rejects.toThrow('Terminal mutation channel closed by client');
        await expect(channel.sendKey({
            authToken: 'TOKEN-123',
            terminalId: 'terminal-1',
            terminalKey: 'enter',
        })).rejects.toThrow('Terminal mutation channel is closed');
    });

    it('rejects connect-in-flight mutation when channel closes before websocket opens', async () => {
        globalThis.WebSocket = MockWebSocket as unknown as typeof WebSocket;
        MockWebSocket.holdOpen = true;
        const channel = createTerminalMutationChannel({
            host: '127.0.0.1',
            port: 29527,
        });

        const pending = channel.sendText({
            authToken: 'TOKEN-123',
            terminalId: 'terminal-1',
            text: 'echo close-during-connect',
        });
        channel.close();

        await expect(Promise.race([
            pending,
            new Promise<never>((_, reject) => {
                setTimeout(() => reject(new Error('connect-close promise did not settle in time')), 250);
            }),
        ])).rejects.toThrow('Terminal mutation channel closed by client');
        expect(MockWebSocket.sentPayloads).toHaveLength(0);
    });
});
