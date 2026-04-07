import { afterEach, describe, expect, it, vi } from 'vitest';

vi.mock('@/encryption/aes', () => ({
    encryptAESGCM: async (data: Uint8Array) => data,
    decryptAESGCM: async (data: Uint8Array) => data,
}));

import {
    readTerminalSemanticDefault,
    readTerminalSemanticV2,
    readTerminalSnapshotDefault,
    readTerminalSnapshotV2,
} from './gateway';

type MessageHandler = ((event: { data?: string }) => void) | null;
type EventHandler = (() => void) | null;

class MockWebSocket {
    static sentPayloads: Array<Record<string, unknown>> = [];
    static openedUrls: string[] = [];
    static responseFactory: ((payload: Record<string, unknown>) => Record<string, unknown>) | null = null;

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
            const response = MockWebSocket.responseFactory
                ? MockWebSocket.responseFactory(parsed)
                : {
                    request_id: parsed.request_id,
                    status: 'ok',
                    result: {},
                };
            this.onmessage?.({
                data: JSON.stringify(response),
            });
        });
    }

    close() {}
}

describe('gateway v2 terminal APIs', () => {
    const originalWebSocket = globalThis.WebSocket;

    afterEach(() => {
        MockWebSocket.sentPayloads = [];
        MockWebSocket.openedUrls = [];
        MockWebSocket.responseFactory = null;
        globalThis.WebSocket = originalWebSocket;
    });

    it('sends terminal.snapshot.v2 and parses snapshot payload', async () => {
        globalThis.WebSocket = MockWebSocket as unknown as typeof WebSocket;
        MockWebSocket.responseFactory = (payload) => ({
            request_id: payload.request_id,
            status: 'ok',
            result: {
                terminal_id: payload.terminal_id,
                generation: 4,
                scope: 'visible',
                snapshot_format: 'ansi_text',
                captured_at: '2026-03-29T00:00:00Z',
                cache_age_ms: 12,
                frame_id: 'frm_2',
                parent_frame_id: 'frm_1',
                content: '\u001B[32mOK\u001B[0m',
            },
        });

        await expect(readTerminalSnapshotV2({
            host: '127.0.0.1',
            port: 29527,
            authToken: 'TOKEN-123',
            terminalId: 'terminal-1',
        })).resolves.toMatchObject({
            terminalId: 'terminal-1',
            generation: 4,
            scope: 'visible',
            snapshotFormat: 'ansi_text',
            frameId: 'frm_2',
            parentFrameId: 'frm_1',
            content: '\u001B[32mOK\u001B[0m',
        });

        expect(MockWebSocket.sentPayloads).toHaveLength(1);
        expect(MockWebSocket.sentPayloads[0]).toMatchObject({
            command: 'terminal.snapshot.v2',
            auth_token: 'TOKEN-123',
            terminal_id: 'terminal-1',
            scope: 'visible',
        });
    });

    it('sends terminal.semantic.v2 and parses logical lines payload', async () => {
        globalThis.WebSocket = MockWebSocket as unknown as typeof WebSocket;
        MockWebSocket.responseFactory = (payload) => ({
            request_id: payload.request_id,
            status: 'ok',
            result: {
                terminal_id: payload.terminal_id,
                generation: 7,
                scope: 'visible',
                extracted_at: '2026-03-29T01:00:00Z',
                logical_lines: ['$ ls', 'README.md'],
                exact_text: '$ ls\nREADME.md',
                prompt_detected: true,
            },
        });

        await expect(readTerminalSemanticV2({
            host: '127.0.0.1',
            port: 29527,
            authToken: 'TOKEN-123',
            terminalId: 'terminal-2',
        })).resolves.toMatchObject({
            terminalId: 'terminal-2',
            generation: 7,
            scope: 'visible',
            logicalLines: ['$ ls', 'README.md'],
            exactText: '$ ls\nREADME.md',
            promptDetected: true,
        });

        expect(MockWebSocket.sentPayloads).toHaveLength(1);
        expect(MockWebSocket.sentPayloads[0]).toMatchObject({
            command: 'terminal.semantic.v2',
            auth_token: 'TOKEN-123',
            terminal_id: 'terminal-2',
            scope: 'visible',
        });
    });

    it('includes desktop_id routing on relay v2 reads', async () => {
        globalThis.WebSocket = MockWebSocket as unknown as typeof WebSocket;
        MockWebSocket.responseFactory = (payload) => ({
            request_id: payload.request_id,
            status: 'ok',
            result: {
                terminal_id: 'terminal-8',
                generation: 8,
                scope: 'visible',
                snapshot_format: 'ansi_text',
                captured_at: '2026-03-29T01:30:00Z',
                cache_age_ms: 10,
                frame_id: 'frm_8',
                parent_frame_id: 'frm_7',
                content: 'relay snapshot',
            },
        });

        await expect(readTerminalSnapshotV2({
            host: '127.0.0.1',
            port: 29527,
            desktopId: 'desktop-relay-v2',
            transportMode: 'relay',
            publicEndpoint: 'wss://edge.example.test/gateway',
            transportSharedSecret: 'relay-secret',
            authToken: 'TOKEN-123',
            terminalId: 'terminal-8',
        })).resolves.toMatchObject({
            terminalId: 'terminal-8',
            generation: 8,
            content: 'relay snapshot',
        });

        expect(MockWebSocket.openedUrls).toEqual(['wss://edge.example.test/gateway?desktop_id=desktop-relay-v2']);
    });

    it('fails fast when terminal_id is empty for v2 reads', async () => {
        globalThis.WebSocket = MockWebSocket as unknown as typeof WebSocket;

        await expect(readTerminalSnapshotV2({
            host: '127.0.0.1',
            port: 29527,
            authToken: 'TOKEN-123',
            terminalId: '   ',
        })).rejects.toThrow('terminal_id is empty');

        await expect(readTerminalSemanticV2({
            host: '127.0.0.1',
            port: 29527,
            authToken: 'TOKEN-123',
            terminalId: '',
        })).rejects.toThrow('terminal_id is empty');

        expect(MockWebSocket.sentPayloads).toHaveLength(0);
        expect(MockWebSocket.openedUrls).toHaveLength(0);
    });
    it('uses semantic.v2 as the default semantic-first read path', async () => {
        globalThis.WebSocket = MockWebSocket as unknown as typeof WebSocket;
        MockWebSocket.responseFactory = (payload) => ({
            request_id: payload.request_id,
            status: 'ok',
            result: {
                terminal_id: payload.terminal_id,
                generation: 11,
                scope: 'visible',
                extracted_at: '2026-03-29T03:00:00Z',
                logical_lines: ['done'],
                exact_text: 'done',
                prompt_detected: false,
            },
        });

        await expect(readTerminalSemanticDefault({
            host: '127.0.0.1',
            port: 29527,
            authToken: 'TOKEN-123',
            terminalId: 'terminal-3',
        })).resolves.toMatchObject({
            kind: 'semantic',
            result: {
                terminalId: 'terminal-3',
                generation: 11,
                logicalLines: ['done'],
            },
        });

        expect(MockWebSocket.sentPayloads).toHaveLength(1);
        expect(MockWebSocket.sentPayloads[0]).toMatchObject({
            command: 'terminal.semantic.v2',
            terminal_id: 'terminal-3',
        });
    });

    it('falls back to snapshot.v2 when semantic.v2 is unsupported', async () => {
        globalThis.WebSocket = MockWebSocket as unknown as typeof WebSocket;
        MockWebSocket.responseFactory = (payload) => {
            if (payload.command === 'terminal.semantic.v2') {
                return {
                    request_id: payload.request_id,
                    status: 'error',
                    error_code: 'unsupported_command',
                    error_message: 'semantic not supported',
                };
            }

            return {
                request_id: payload.request_id,
                status: 'ok',
                result: {
                    terminal_id: payload.terminal_id,
                    generation: 12,
                    scope: 'visible',
                    snapshot_format: 'ansi_text',
                    captured_at: '2026-03-29T03:01:00Z',
                    cache_age_ms: 6,
                    frame_id: 'frm_12',
                    parent_frame_id: 'frm_11',
                    content: 'fallback snapshot',
                },
            };
        };

        await expect(readTerminalSemanticDefault({
            host: '127.0.0.1',
            port: 29527,
            authToken: 'TOKEN-123',
            terminalId: 'terminal-4',
        })).resolves.toMatchObject({
            kind: 'snapshot',
            result: {
                terminalId: 'terminal-4',
                generation: 12,
                frameId: 'frm_12',
                content: 'fallback snapshot',
            },
        });

        expect(MockWebSocket.sentPayloads).toHaveLength(2);
        expect(MockWebSocket.sentPayloads[0]).toMatchObject({ command: 'terminal.semantic.v2' });
        expect(MockWebSocket.sentPayloads[1]).toMatchObject({ command: 'terminal.snapshot.v2' });
    });

    it('falls back to read-terminal snapshot when terminal.snapshot.v2 is unsupported', async () => {
        globalThis.WebSocket = MockWebSocket as unknown as typeof WebSocket;
        MockWebSocket.responseFactory = (payload) => {
            if (payload.command === 'terminal.snapshot.v2') {
                return {
                    request_id: payload.request_id,
                    status: 'error',
                    error_code: 'unsupported_command',
                    error_message: 'snapshot v2 not supported',
                };
            }

            return {
                request_id: payload.request_id,
                status: 'ok',
                result: {
                    terminal_id: payload.terminal_id,
                    generation: 13,
                    scope: 'visible',
                    mode: 'snapshot',
                    captured_at: '2026-03-29T03:02:00Z',
                    cache_age_ms: 5,
                    frame_id: 'frm_13',
                    parent_frame_id: 'frm_12',
                    has_changes: true,
                    content: 'legacy snapshot fallback',
                },
            };
        };

        await expect(readTerminalSnapshotDefault({
            host: '127.0.0.1',
            port: 29527,
            authToken: 'TOKEN-123',
            terminalId: 'terminal-5',
        })).resolves.toMatchObject({
            terminalId: 'terminal-5',
            generation: 13,
            snapshotFormat: 'legacy_read_terminal',
            frameId: 'frm_13',
            content: 'legacy snapshot fallback',
        });

        expect(MockWebSocket.sentPayloads).toHaveLength(2);
        expect(MockWebSocket.sentPayloads[0]).toMatchObject({ command: 'terminal.snapshot.v2' });
        expect(MockWebSocket.sentPayloads[1]).toMatchObject({
            command: 'read-terminal',
            mode: 'snapshot',
            scope: 'visible',
        });
    });

    it('falls back to read-terminal snapshot when semantic.v2 and snapshot.v2 are both unsupported', async () => {
        globalThis.WebSocket = MockWebSocket as unknown as typeof WebSocket;
        MockWebSocket.responseFactory = (payload) => {
            if (payload.command === 'terminal.semantic.v2' || payload.command === 'terminal.snapshot.v2') {
                return {
                    request_id: payload.request_id,
                    status: 'error',
                    error_code: 'unsupported_command',
                    error_message: 'v2 not supported',
                };
            }

            return {
                request_id: payload.request_id,
                status: 'ok',
                result: {
                    terminal_id: payload.terminal_id,
                    generation: 14,
                    scope: 'visible',
                    mode: 'snapshot',
                    captured_at: '2026-03-29T03:03:00Z',
                    cache_age_ms: 4,
                    frame_id: 'frm_14',
                    parent_frame_id: 'frm_13',
                    has_changes: true,
                    content: 'semantic legacy fallback',
                },
            };
        };

        await expect(readTerminalSemanticDefault({
            host: '127.0.0.1',
            port: 29527,
            authToken: 'TOKEN-123',
            terminalId: 'terminal-6',
        })).resolves.toMatchObject({
            kind: 'snapshot',
            result: {
                terminalId: 'terminal-6',
                generation: 14,
                snapshotFormat: 'legacy_read_terminal',
                frameId: 'frm_14',
                content: 'semantic legacy fallback',
            },
        });

        expect(MockWebSocket.sentPayloads).toHaveLength(3);
        expect(MockWebSocket.sentPayloads[0]).toMatchObject({ command: 'terminal.semantic.v2' });
        expect(MockWebSocket.sentPayloads[1]).toMatchObject({ command: 'terminal.snapshot.v2' });
        expect(MockWebSocket.sentPayloads[2]).toMatchObject({
            command: 'read-terminal',
            mode: 'snapshot',
            scope: 'visible',
        });
    });
});
