import type {
    GatewayConnection,
    GatewayEnvelope,
    PairingBeginResult,
    PairingExchangeResult,
    SnapshotResult,
    TabMutationResult,
    TabRow,
    TerminalChangedRow,
    TerminalMutationResult,
    TerminalReadResult,
    TerminalStreamAckResult,
    TerminalStreamChunkRecord,
    TerminalStreamOpenResult,
    TerminalSemanticV2Result,
    TerminalSnapshotV2Result,
    TerminalRow,
} from './types';
import {
    decodeEncryptedGatewayEnvelope,
    encodeEncryptedGatewayRequest,
    resolveGatewaySocketUrl,
    usesEncryptedGatewayTransport,
} from './transport';

const DEFAULT_TIMEOUT_MS = 10_000;

export const DEFAULT_REQUESTED_SCOPES = ['observe', 'mutate'] as const;

class GatewayProtocolError extends Error {
    constructor(message: string, public readonly code?: string) {
        super(message);
        this.name = 'GatewayProtocolError';
    }
}

interface GatewayRequest {
    request_id: string;
    command: string;
    auth_token?: string;
    client?: string;
    device_id?: string;
    device_label?: string;
    requested_scopes?: string[];
    pairing_code?: string;
    tab_id?: string;
    parent_tab_id?: string;
    terminal_id?: string;
    scope?: string;
    mode?: string;
    command_text?: string;
    text?: string;
    terminal_key?: string;
    stream_id?: string;
    ack_bytes?: number;
    working_directory?: string;
    title?: string;
    force?: boolean;
    expected_generation?: number;
    since_frame_id?: string;
    max_chars?: number;
    max_lines?: number;
    read_after_write_id?: string;
    since_sequence?: number;
    event_limit?: number;
}

function nextRequestId(prefix: string): string {
    return `${prefix}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
}

function ensureObject(value: unknown, label: string): Record<string, unknown> {
    if (!value || typeof value !== 'object' || Array.isArray(value)) {
        throw new GatewayProtocolError(`Invalid ${label} from gateway`);
    }
    return value as Record<string, unknown>;
}

function readString(object: Record<string, unknown>, ...keys: string[]): string | null {
    for (const key of keys) {
        const value = object[key];
        if (typeof value === 'string') {
            return value;
        }
    }
    return null;
}

function readNumber(object: Record<string, unknown>, key: string): number {
    const value = object[key];
    return typeof value === 'number' && Number.isFinite(value) ? value : 0;
}

function readBoolean(object: Record<string, unknown>, key: string): boolean {
    return object[key] === true;
}

function readStringArray(object: Record<string, unknown>, key: string): string[] {
    const value = object[key];
    if (!Array.isArray(value)) {
        return [];
    }
    return value.filter((item): item is string => typeof item === 'string');
}

function readChangedRows(object: Record<string, unknown>, key: string): TerminalChangedRow[] {
    const value = object[key];
    if (!Array.isArray(value)) {
        return [];
    }

    return value.flatMap((item) => {
        if (!item || typeof item !== 'object' || Array.isArray(item)) {
            return [];
        }

        const row = item as Record<string, unknown>;
        const index = typeof row.index === 'number' && Number.isFinite(row.index) ? row.index : -1;
        if (index < 0) {
            return [];
        }

        return [{
            index,
            kind: readString(row, 'kind') ?? 'update',
            text: readString(row, 'text'),
        }];
    });
}

function parseEnvelope(rawText: string): GatewayEnvelope {
    const parsed = ensureObject(JSON.parse(rawText), 'envelope');
    return parsed as GatewayEnvelope;
}

export function parseGatewayEnvelope(rawText: string): GatewayEnvelope {
    return parseEnvelope(rawText);
}

async function parseReceivedEnvelope(
    rawText: string,
    connection: GatewayConnection,
): Promise<GatewayEnvelope> {
    const envelope = parseEnvelope(rawText);
    if (!usesEncryptedGatewayTransport(connection) || typeof envelope.encrypted_payload !== 'string') {
        return envelope;
    }
    const decrypted = await decodeEncryptedGatewayEnvelope({
        encryptedEnvelope: {
            transport_mode: typeof envelope.transport_mode === 'string' ? envelope.transport_mode : undefined,
            encrypted_payload: envelope.encrypted_payload,
        },
        transportSharedSecret: connection.transportSharedSecret!.trim(),
    });
    return decrypted as GatewayEnvelope;
}

function relayFallbackConnection(connection: GatewayConnection): GatewayConnection | null {
    if (connection.transportMode === 'relay') {
        return null;
    }
    if (!connection.publicEndpoint?.trim() || !connection.transportSharedSecret?.trim()) {
        return null;
    }
    return {
        ...connection,
        transportMode: 'relay',
    };
}

async function sendRequestOnce(connection: GatewayConnection, request: GatewayRequest): Promise<GatewayEnvelope> {
    const url = resolveGatewaySocketUrl({
        transportMode: connection.transportMode === 'relay' ? 'relay' : 'lan',
        host: connection.host,
        port: connection.port,
        publicEndpoint: connection.publicEndpoint,
        transportSharedSecret: connection.transportSharedSecret,
    });

    return new Promise<GatewayEnvelope>((resolve, reject) => {
        let settled = false;
        const socket = new WebSocket(url);
        const timer = setTimeout(() => {
            if (settled) {
                return;
            }
            settled = true;
            socket.close();
            reject(new GatewayProtocolError(`Gateway request timed out after ${DEFAULT_TIMEOUT_MS}ms`));
        }, DEFAULT_TIMEOUT_MS);

        const cleanup = () => {
            clearTimeout(timer);
            socket.onopen = null;
            socket.onmessage = null;
            socket.onerror = null;
            socket.onclose = null;
        };

        socket.onopen = () => {
            if (usesEncryptedGatewayTransport(connection)) {
                void encodeEncryptedGatewayRequest({
                    request: request as unknown as Record<string, unknown>,
                    authToken: request.auth_token ?? '',
                    transportSharedSecret: connection.transportSharedSecret!.trim(),
                }).then((encryptedRequest) => {
                    socket.send(JSON.stringify(encryptedRequest));
                }).catch((error) => {
                    if (settled) {
                        return;
                    }
                    settled = true;
                    cleanup();
                    socket.close();
                    reject(error instanceof Error ? error : new GatewayProtocolError('Failed to encrypt gateway request'));
                });
                return;
            }
            socket.send(JSON.stringify(request));
        };

        socket.onmessage = async (event) => {
            if (settled) {
                return;
            }
            settled = true;
            cleanup();
            socket.close();

            try {
                const rawText = typeof event.data === 'string' ? event.data : String(event.data ?? '');
                const envelope = await parseReceivedEnvelope(rawText, connection);
                if (envelope.status === 'error') {
                    reject(new GatewayProtocolError(
                        envelope.error_message ?? envelope.error_code ?? 'Gateway rejected request',
                        envelope.error_code,
                    ));
                    return;
                }
                resolve(envelope);
            } catch (error) {
                reject(error instanceof Error ? error : new GatewayProtocolError('Invalid gateway response'));
            }
        };

        socket.onerror = () => {
            if (settled) {
                return;
            }
            settled = true;
            cleanup();
            reject(new GatewayProtocolError(`Unable to open WebSocket to ${url}`));
        };

        socket.onclose = (event) => {
            if (settled) {
                return;
            }
            settled = true;
            cleanup();
            reject(new GatewayProtocolError(
                event.reason || `Gateway socket closed before reply (code ${event.code})`,
            ));
        };
    });
}

async function sendRequest(connection: GatewayConnection, request: GatewayRequest): Promise<GatewayEnvelope> {
    try {
        return await sendRequestOnce(connection, request);
    } catch (error) {
        const relayConnection = relayFallbackConnection(connection);
        if (!relayConnection) {
            throw error;
        }
        return sendRequestOnce(relayConnection, request);
    }
}

function parsePairingBeginResult(envelope: GatewayEnvelope): PairingBeginResult {
    const result = ensureObject(envelope.result, 'pairing begin result');
    const pairingCode = readString(result, 'pairing_code');
    if (!pairingCode) {
        throw new GatewayProtocolError('Gateway pairing begin response is missing pairing_code');
    }

    return {
        pairingCode,
        client: readString(result, 'client'),
        scopes: readStringArray(result, 'scopes'),
    };
}

function parsePairingExchangeResult(envelope: GatewayEnvelope): PairingExchangeResult {
    const result = ensureObject(envelope.result, 'pairing exchange result');
    const authToken = readString(result, 'auth_token', 'token');
    if (!authToken) {
        throw new GatewayProtocolError('Gateway pairing exchange response is missing auth token');
    }

    return {
        authToken,
        tokenId: readString(result, 'token_id'),
        scopes: readStringArray(result, 'scopes'),
        desktopId: readString(result, 'desktop_id'),
        desktopLabel: readString(result, 'desktop_label'),
        preferredDesktopId: readString(result, 'preferred_desktop_id'),
        transportMode: readString(result, 'transport_mode'),
        publicEndpoint: readString(result, 'public_endpoint'),
        transportSharedSecret: readString(result, 'transport_shared_secret'),
    };
}

function parseTabRows(result: Record<string, unknown>): TabRow[] {
    const tabsValue = result.tabs;
    if (!Array.isArray(tabsValue)) {
        return [];
    }

    return tabsValue.flatMap((tab) => {
        if (!tab || typeof tab !== 'object' || Array.isArray(tab)) {
            return [];
        }

        const tabObject = tab as Record<string, unknown>;
        const tabId = readString(tabObject, 'tab_id');
        if (!tabId) {
            return [];
        }

        const terminalList = Array.isArray(tabObject.terminals) ? tabObject.terminals : [];
        const terminals = terminalList.flatMap((terminal) => {
            if (!terminal || typeof terminal !== 'object' || Array.isArray(terminal)) {
                return [];
            }

            const terminalObject = terminal as Record<string, unknown>;
            const terminalId = readString(terminalObject, 'terminal_id');
            if (!terminalId) {
                return [];
            }

            return [{
                tabId,
                terminalId,
                generation: readNumber(terminalObject, 'generation'),
                title: readString(terminalObject, 'title'),
                workingDirectory: readString(terminalObject, 'working_directory'),
                focused: readBoolean(terminalObject, 'is_focused'),
                visible: readBoolean(terminalObject, 'is_visible'),
            }];
        });

        return [{
            tabId,
            generation: readNumber(tabObject, 'generation'),
            windowNumber: readNumber(tabObject, 'window_number'),
            title: readString(tabObject, 'title'),
            focused: readBoolean(tabObject, 'is_focused'),
            isMainWindow: readBoolean(tabObject, 'is_main_window'),
            hasBell: readBoolean(tabObject, 'has_bell'),
            terminals,
        }];
    });
}

function flattenTerminalRows(tabs: TabRow[]): TerminalRow[] {
    return tabs.flatMap((tab) => tab.terminals);
}

function parseSnapshotResult(envelope: GatewayEnvelope): SnapshotResult {
    const result = ensureObject(envelope.result, 'snapshot result');
    const tabs = parseTabRows(result);
    return {
        protocolVersion: readString(result, 'protocol_version'),
        lastSequence: readNumber(result, 'last_sequence'),
        tabs,
        terminals: flattenTerminalRows(tabs),
    };
}

function parseTerminalReadResult(envelope: GatewayEnvelope): TerminalReadResult {
    const result = ensureObject(envelope.result, 'terminal read result');
    const terminalId = readString(result, 'terminal_id');
    if (!terminalId) {
        throw new GatewayProtocolError('Gateway terminal read response is missing terminal_id');
    }

    return {
        terminalId,
        generation: readNumber(result, 'generation'),
        scope: readString(result, 'scope') ?? 'visible',
        mode: readString(result, 'mode') ?? 'snapshot',
        contentKind: readString(result, 'content_kind') ?? 'snapshot',
        consistency: readString(result, 'consistency') ?? 'unknown',
        capturedAt: readString(result, 'captured_at'),
        cacheAgeMs: readNumber(result, 'cache_age_ms'),
        lastSequence: readNumber(result, 'last_sequence'),
        frameId: readString(result, 'frame_id'),
        parentFrameId: readString(result, 'parent_frame_id'),
        hasChanges: readBoolean(result, 'has_changes'),
        deltaKind: readString(result, 'delta_kind'),
        deltaText: readString(result, 'delta_text'),
        changedRows: readChangedRows(result, 'changed_rows'),
        totalLines: readNumber(result, 'total_lines'),
        returnedLines: readNumber(result, 'returned_lines'),
        truncated: readBoolean(result, 'truncated'),
        nextCursor: readString(result, 'next_cursor'),
        observedWriteId: readString(result, 'observed_write_id'),
        readAfterReady: typeof result.read_after_ready === 'boolean' ? result.read_after_ready : null,
        content: readString(result, 'content') ?? '',
    };
}

function parseTerminalSnapshotV2Result(envelope: GatewayEnvelope): TerminalSnapshotV2Result {
    const result = ensureObject(envelope.result, 'terminal snapshot v2 result');
    const terminalId = readString(result, 'terminal_id');
    if (!terminalId) {
        throw new GatewayProtocolError('Gateway terminal snapshot v2 response is missing terminal_id');
    }

    return {
        terminalId,
        generation: readNumber(result, 'generation'),
        scope: readString(result, 'scope') ?? 'visible',
        snapshotFormat: readString(result, 'snapshot_format') ?? 'ansi_text',
        capturedAt: readString(result, 'captured_at'),
        cacheAgeMs: readNumber(result, 'cache_age_ms'),
        frameId: readString(result, 'frame_id'),
        parentFrameId: readString(result, 'parent_frame_id'),
        content: readString(result, 'content') ?? '',
    };
}

function parseTerminalSemanticV2Result(envelope: GatewayEnvelope): TerminalSemanticV2Result {
    const result = ensureObject(envelope.result, 'terminal semantic v2 result');
    const terminalId = readString(result, 'terminal_id');
    if (!terminalId) {
        throw new GatewayProtocolError('Gateway terminal semantic v2 response is missing terminal_id');
    }

    return {
        terminalId,
        generation: readNumber(result, 'generation'),
        scope: readString(result, 'scope') ?? 'visible',
        extractedAt: readString(result, 'extracted_at'),
        logicalLines: readStringArray(result, 'logical_lines'),
        exactText: readString(result, 'exact_text') ?? '',
        promptDetected: readBoolean(result, 'prompt_detected'),
    };
}

function parseTerminalStreamOpenResult(envelope: GatewayEnvelope): TerminalStreamOpenResult {
    const result = ensureObject(envelope.result, 'terminal stream open result');
    const streamId = readString(result, 'stream_id');
    const terminalId = readString(result, 'terminal_id');
    if (!streamId) {
        throw new GatewayProtocolError('Gateway terminal stream open response is missing stream_id');
    }
    if (!terminalId) {
        throw new GatewayProtocolError('Gateway terminal stream open response is missing terminal_id');
    }

    return {
        protocolVersion: readString(result, 'protocol_version'),
        streamId,
        terminalId,
        generation: readNumber(result, 'generation'),
        mode: readString(result, 'mode') ?? 'stream',
        lastSequence: readNumber(result, 'last_sequence'),
        liveStreamOpen: readBoolean(result, 'live_stream_open'),
        highWatermarkBytes: readNumber(result, 'high_watermark_bytes'),
        lowWatermarkBytes: readNumber(result, 'low_watermark_bytes'),
        unackedBytes: readNumber(result, 'unacked_bytes'),
        flowPaused: readBoolean(result, 'flow_paused'),
    };
}

function parseTerminalStreamChunkRecord(raw: Record<string, unknown>): TerminalStreamChunkRecord | null {
    if (readString(raw, 'stream_kind') !== 'terminal_chunk') {
        return null;
    }

    const streamId = readString(raw, 'stream_id');
    const terminalId = readString(raw, 'terminal_id');
    const frameId = readString(raw, 'frame_id');
    if (!streamId || !terminalId || !frameId) {
        throw new GatewayProtocolError('Gateway terminal stream chunk is missing required identifiers');
    }

    const content = readString(raw, 'content') ?? '';
    const contentLength = readNumber(raw, 'content_length') || content.length;

    return {
        streamKind: 'terminal_chunk',
        streamId,
        terminalId,
        generation: readNumber(raw, 'generation'),
        frameId,
        parentFrameId: readString(raw, 'parent_frame_id'),
        deltaKind: readString(raw, 'delta_kind') ?? 'snapshot',
        content,
        contentLength,
        changedRows: readChangedRows(raw, 'changed_rows'),
    };
}

function parseTerminalStreamAckResult(envelope: GatewayEnvelope): TerminalStreamAckResult {
    const result = ensureObject(envelope.result, 'terminal stream ack result');
    const streamId = readString(result, 'stream_id');
    const terminalId = readString(result, 'terminal_id');
    if (!streamId) {
        throw new GatewayProtocolError('Gateway terminal stream ack response is missing stream_id');
    }
    if (!terminalId) {
        throw new GatewayProtocolError('Gateway terminal stream ack response is missing terminal_id');
    }

    return {
        terminalId,
        streamId,
        generation: readNumber(result, 'generation'),
        acknowledgedBytes: readNumber(result, 'acknowledged_bytes'),
        remainingUnackedBytes: readNumber(result, 'remaining_unacked_bytes'),
        highWatermarkBytes: readNumber(result, 'high_watermark_bytes'),
        lowWatermarkBytes: readNumber(result, 'low_watermark_bytes'),
        flowPaused: readBoolean(result, 'flow_paused'),
    };
}

function parseTerminalMutationResult(envelope: GatewayEnvelope): TerminalMutationResult {
    const result = ensureObject(envelope.result, 'terminal mutation result');
    const terminalId = readString(result, 'terminal_id');
    if (!terminalId) {
        throw new GatewayProtocolError('Gateway terminal mutation response is missing terminal_id');
    }

    return {
        terminalId,
        generation: readNumber(result, 'generation'),
        sequence: readNumber(result, 'sequence'),
        operation: readString(result, 'operation'),
        acknowledged: readBoolean(result, 'acknowledged'),
        writeId: readString(result, 'write_id'),
    };
}

function parseTabMutationResult(envelope: GatewayEnvelope): TabMutationResult {
    const result = ensureObject(envelope.result, 'tab mutation result');
    const tabId = readString(result, 'tab_id');
    if (!tabId) {
        throw new GatewayProtocolError('Gateway tab mutation response is missing tab_id');
    }

    return {
        tabId,
        generation: readNumber(result, 'tab_generation') || readNumber(result, 'generation'),
        sequence: readNumber(result, 'sequence'),
        terminalId: readString(result, 'terminal_id'),
        terminalGeneration: typeof result.terminal_generation === 'number' && Number.isFinite(result.terminal_generation)
            ? result.terminal_generation
            : null,
        title: readString(result, 'title'),
        closed: readBoolean(result, 'closed'),
        requiresConfirmation: readBoolean(result, 'requires_confirmation'),
        confirmationTitle: readString(result, 'confirmation_title'),
        confirmationMessage: readString(result, 'confirmation_message'),
    };
}

export async function pairingBegin(input: GatewayConnection & {
    client: string;
    deviceId: string;
    deviceLabel: string;
    requestedScopes?: readonly string[];
}): Promise<PairingBeginResult> {
    const envelope = await sendRequest(
        input,
        {
            request_id: nextRequestId('pair-begin'),
            command: 'gateway.pairing.begin',
            client: input.client,
            device_id: input.deviceId.trim(),
            device_label: input.deviceLabel.trim(),
            requested_scopes: [...(input.requestedScopes ?? DEFAULT_REQUESTED_SCOPES)],
        },
    );
    return parsePairingBeginResult(envelope);
}

export async function pairingExchange(input: GatewayConnection & {
    pairingCode: string;
}): Promise<PairingExchangeResult> {
    const pairingCode = input.pairingCode.trim();
    if (!pairingCode) {
        throw new GatewayProtocolError('Pairing code is empty');
    }

    const envelope = await sendRequest(
        input,
        {
            request_id: nextRequestId('pair-exchange'),
            command: 'gateway.pairing.exchange',
            pairing_code: pairingCode,
        },
    );
    return parsePairingExchangeResult(envelope);
}

export async function fetchSnapshot(input: GatewayConnection & {
    authToken: string;
}): Promise<SnapshotResult> {
    const authToken = input.authToken.trim();
    if (!authToken) {
        throw new GatewayProtocolError('Auth token is empty');
    }

    const envelope = await sendRequest(
        input,
        {
            request_id: nextRequestId('snapshot'),
            command: 'snapshot',
            auth_token: authToken,
        },
    );
    return parseSnapshotResult(envelope);
}

export async function readTerminal(input: GatewayConnection & {
    authToken: string;
    terminalId: string;
    expectedGeneration?: number;
    scope?: 'visible' | 'screen';
    mode?: 'snapshot' | 'delta';
    sinceFrameId?: string;
    maxChars?: number;
    maxLines?: number;
    readAfterWriteId?: string;
}): Promise<TerminalReadResult> {
    const authToken = input.authToken.trim();
    const terminalId = input.terminalId.trim();
    if (!authToken) {
        throw new GatewayProtocolError('Auth token is empty');
    }
    if (!terminalId) {
        throw new GatewayProtocolError('terminal_id is empty');
    }

    const envelope = await sendRequest(
        input,
        {
            request_id: nextRequestId('read-terminal'),
            command: 'read-terminal',
            auth_token: authToken,
            terminal_id: terminalId,
            expected_generation: input.expectedGeneration,
            scope: input.scope ?? 'visible',
            mode: input.mode ?? 'snapshot',
            since_frame_id: input.sinceFrameId?.trim() || undefined,
            max_chars: input.maxChars,
            max_lines: input.maxLines,
            read_after_write_id: input.readAfterWriteId?.trim() || undefined,
        },
    );
    return parseTerminalReadResult(envelope);
}

export async function readTerminalSnapshotV2(input: GatewayConnection & {
    authToken: string;
    terminalId: string;
    expectedGeneration?: number;
    scope?: 'visible' | 'screen';
}): Promise<TerminalSnapshotV2Result> {
    const authToken = input.authToken.trim();
    const terminalId = input.terminalId.trim();
    if (!authToken) {
        throw new GatewayProtocolError('Auth token is empty');
    }
    if (!terminalId) {
        throw new GatewayProtocolError('terminal_id is empty');
    }

    const envelope = await sendRequest(
        input,
        {
            request_id: nextRequestId('terminal-snapshot-v2'),
            command: 'terminal.snapshot.v2',
            auth_token: authToken,
            terminal_id: terminalId,
            expected_generation: input.expectedGeneration,
            scope: input.scope ?? 'visible',
        },
    );
    return parseTerminalSnapshotV2Result(envelope);
}

export async function readTerminalSemanticV2(input: GatewayConnection & {
    authToken: string;
    terminalId: string;
    expectedGeneration?: number;
    scope?: 'visible' | 'screen';
}): Promise<TerminalSemanticV2Result> {
    const authToken = input.authToken.trim();
    const terminalId = input.terminalId.trim();
    if (!authToken) {
        throw new GatewayProtocolError('Auth token is empty');
    }
    if (!terminalId) {
        throw new GatewayProtocolError('terminal_id is empty');
    }

    const envelope = await sendRequest(
        input,
        {
            request_id: nextRequestId('terminal-semantic-v2'),
            command: 'terminal.semantic.v2',
            auth_token: authToken,
            terminal_id: terminalId,
            expected_generation: input.expectedGeneration,
            scope: input.scope ?? 'visible',
        },
    );
    return parseTerminalSemanticV2Result(envelope);
}

export async function ackTerminalStream(input: GatewayConnection & {
    authToken: string;
    terminalId: string;
    streamId: string;
    ackBytes: number;
    expectedGeneration?: number;
}): Promise<TerminalStreamAckResult> {
    const authToken = input.authToken.trim();
    const terminalId = input.terminalId.trim();
    const streamId = input.streamId.trim();
    const ackBytes = Math.max(1, Math.trunc(input.ackBytes));
    if (!authToken) {
        throw new GatewayProtocolError('Auth token is empty');
    }
    if (!terminalId) {
        throw new GatewayProtocolError('terminal_id is empty');
    }
    if (!streamId) {
        throw new GatewayProtocolError('stream_id is empty');
    }

    const envelope = await sendRequest(
        input,
        {
            request_id: nextRequestId('terminal-stream-ack'),
            command: 'terminal.stream.ack',
            auth_token: authToken,
            terminal_id: terminalId,
            stream_id: streamId,
            ack_bytes: ackBytes,
            expected_generation: input.expectedGeneration,
        },
    );
    return parseTerminalStreamAckResult(envelope);
}

export function subscribeToTerminalStream(input: GatewayConnection & {
    authToken: string;
    terminalId: string;
    expectedGeneration?: number;
    scope?: 'visible' | 'screen';
    onOpen: (open: TerminalStreamOpenResult) => void;
    onChunk: (chunk: TerminalStreamChunkRecord) => void;
    onError?: (error: Error) => void;
}): () => void {
    const authToken = input.authToken.trim();
    const terminalId = input.terminalId.trim();
    if (!authToken) {
        throw new GatewayProtocolError('Auth token is empty');
    }
    if (!terminalId) {
        throw new GatewayProtocolError('terminal_id is empty');
    }

    const openVariant = (connection: GatewayConnection) => {
        const socket = new WebSocket(resolveGatewaySocketUrl({
            transportMode: connection.transportMode === 'relay' ? 'relay' : 'lan',
            host: connection.host,
            port: connection.port,
            publicEndpoint: connection.publicEndpoint,
            transportSharedSecret: connection.transportSharedSecret,
        }));
        return socket;
    };
    let closedByClient = false;
    let settled = false;
    let attemptedRelayFallback = false;
    let streamOpenAcknowledged = false;
    let socket = openVariant(input);
    let activeConnection: GatewayConnection = input;

    const finalizeWithError = (error: GatewayProtocolError) => {
        if (closedByClient || settled) {
            return;
        }
        settled = true;
        input.onError?.(error);
    };

    const bindSocket = (connection: GatewayConnection) => {
        const boundSocket = socket;

        socket.onopen = () => {
            if (boundSocket !== socket) {
                return;
            }
            const request: GatewayRequest = {
                request_id: nextRequestId('terminal-stream-open'),
                command: 'terminal.stream.open',
                auth_token: authToken,
                terminal_id: terminalId,
                expected_generation: input.expectedGeneration,
                scope: input.scope ?? 'visible',
            };
            if (usesEncryptedGatewayTransport(connection)) {
                void encodeEncryptedGatewayRequest({
                    request: request as unknown as Record<string, unknown>,
                    authToken,
                    transportSharedSecret: connection.transportSharedSecret!.trim(),
                }).then((encryptedRequest) => {
                    socket.send(JSON.stringify(encryptedRequest));
                }).catch((error) => {
                    finalizeWithError(error instanceof Error ? error : new GatewayProtocolError('Failed to encrypt terminal stream request'));
                    socket.close();
                });
                return;
            }
            socket.send(JSON.stringify(request));
        };

        socket.onmessage = async (event) => {
            if (boundSocket !== socket) {
                return;
            }
            try {
                const rawText = typeof event.data === 'string' ? event.data : String(event.data ?? '');
                const envelope = await parseReceivedEnvelope(rawText, connection);
                if (!streamOpenAcknowledged) {
                    if (envelope.status === 'error') {
                        const error = new GatewayProtocolError(
                            envelope.error_message ?? envelope.error_code ?? 'Gateway rejected terminal stream',
                            envelope.error_code,
                        );
                        finalizeWithError(error);
                        socket.close();
                        return;
                    }
                    if (envelope.status === 'ok') {
                        streamOpenAcknowledged = true;
                        input.onOpen(parseTerminalStreamOpenResult(envelope));
                        return;
                    }
                }

                const chunk = parseTerminalStreamChunkRecord(envelope as unknown as Record<string, unknown>);
                if (chunk) {
                    input.onChunk(chunk);
                }
            } catch (error) {
                finalizeWithError(
                    error instanceof GatewayProtocolError
                        ? error
                        : new GatewayProtocolError(
                            error instanceof Error ? error.message : 'Invalid terminal stream payload',
                        ),
                );
                socket.close();
            }
        };

        socket.onerror = () => {
            if (boundSocket !== socket) {
                return;
            }
            const relayConnection = !attemptedRelayFallback ? relayFallbackConnection(activeConnection) : null;
            if (relayConnection) {
                attemptedRelayFallback = true;
                activeConnection = relayConnection;
                socket = openVariant(relayConnection);
                bindSocket(relayConnection);
                return;
            }
            finalizeWithError(new GatewayProtocolError('Gateway terminal stream socket failed'));
        };

        socket.onclose = (event) => {
            if (boundSocket !== socket) {
                return;
            }
            if (closedByClient || settled) {
                return;
            }
            const relayConnection = !attemptedRelayFallback ? relayFallbackConnection(activeConnection) : null;
            if (relayConnection) {
                attemptedRelayFallback = true;
                activeConnection = relayConnection;
                socket = openVariant(relayConnection);
                bindSocket(relayConnection);
                return;
            }
            finalizeWithError(new GatewayProtocolError(
                event.reason || `Gateway terminal stream closed unexpectedly (code ${event.code})`,
            ));
        };
    };

    bindSocket(activeConnection);

    return () => {
        closedByClient = true;
        socket.close();
    };
}

export async function runTerminalCommand(input: GatewayConnection & {
    authToken: string;
    terminalId: string;
    commandText: string;
    expectedGeneration?: number;
}): Promise<TerminalMutationResult> {
    const authToken = input.authToken.trim();
    const terminalId = input.terminalId.trim();
    const commandText = input.commandText.trim();
    if (!authToken) {
        throw new GatewayProtocolError('Auth token is empty');
    }
    if (!terminalId) {
        throw new GatewayProtocolError('terminal_id is empty');
    }
    if (!commandText) {
        throw new GatewayProtocolError('command_text is empty');
    }

    const envelope = await sendRequest(
        input,
        {
            request_id: nextRequestId('run-command'),
            command: 'run-command',
            auth_token: authToken,
            terminal_id: terminalId,
            command_text: commandText,
            expected_generation: input.expectedGeneration,
        },
    );
    return parseTerminalMutationResult(envelope);
}

export async function createTab(input: GatewayConnection & {
    authToken: string;
    parentTabId?: string;
    title?: string;
    workingDirectory?: string;
}): Promise<TabMutationResult> {
    const authToken = input.authToken.trim();
    if (!authToken) {
        throw new GatewayProtocolError('Auth token is empty');
    }

    const envelope = await sendRequest(
        input,
        {
            request_id: nextRequestId('new-tab'),
            command: 'new-tab',
            auth_token: authToken,
            parent_tab_id: input.parentTabId?.trim() || undefined,
            title: input.title?.trim() || undefined,
            working_directory: input.workingDirectory?.trim() || undefined,
        },
    );
    return parseTabMutationResult(envelope);
}

export async function closeTab(input: GatewayConnection & {
    authToken: string;
    tabId: string;
    expectedGeneration?: number;
    force?: boolean;
}): Promise<TabMutationResult> {
    const authToken = input.authToken.trim();
    const tabId = input.tabId.trim();
    if (!authToken) {
        throw new GatewayProtocolError('Auth token is empty');
    }
    if (!tabId) {
        throw new GatewayProtocolError('tab_id is empty');
    }

    const envelope = await sendRequest(
        input,
        {
            request_id: nextRequestId('close-tab'),
            command: 'close-tab',
            auth_token: authToken,
            tab_id: tabId,
            expected_generation: input.expectedGeneration,
            force: input.force,
        },
    );
    return parseTabMutationResult(envelope);
}

export async function renameTab(input: GatewayConnection & {
    authToken: string;
    tabId: string;
    title: string;
    expectedGeneration?: number;
}): Promise<TabMutationResult> {
    const authToken = input.authToken.trim();
    const tabId = input.tabId.trim();
    if (!authToken) {
        throw new GatewayProtocolError('Auth token is empty');
    }
    if (!tabId) {
        throw new GatewayProtocolError('tab_id is empty');
    }

    const envelope = await sendRequest(
        input,
        {
            request_id: nextRequestId('rename-tab'),
            command: 'rename-tab',
            auth_token: authToken,
            tab_id: tabId,
            title: input.title.trim(),
            expected_generation: input.expectedGeneration,
        },
    );
    return parseTabMutationResult(envelope);
}

export async function sendTerminalText(input: GatewayConnection & {
    authToken: string;
    terminalId: string;
    text: string;
    expectedGeneration?: number;
}): Promise<TerminalMutationResult> {
    const authToken = input.authToken.trim();
    const terminalId = input.terminalId.trim();
    if (!authToken) {
        throw new GatewayProtocolError('Auth token is empty');
    }
    if (!terminalId) {
        throw new GatewayProtocolError('terminal_id is empty');
    }
    if (!input.text) {
        throw new GatewayProtocolError('text is empty');
    }

    const envelope = await sendRequest(
        input,
        {
            request_id: nextRequestId('send-text'),
            command: 'send-text',
            auth_token: authToken,
            terminal_id: terminalId,
            text: input.text,
            expected_generation: input.expectedGeneration,
        },
    );
    return parseTerminalMutationResult(envelope);
}

export async function sendTerminalKey(input: GatewayConnection & {
    authToken: string;
    terminalId: string;
    terminalKey: string;
    expectedGeneration?: number;
}): Promise<TerminalMutationResult> {
    const authToken = input.authToken.trim();
    const terminalId = input.terminalId.trim();
    const terminalKey = input.terminalKey.trim();
    if (!authToken) {
        throw new GatewayProtocolError('Auth token is empty');
    }
    if (!terminalId) {
        throw new GatewayProtocolError('terminal_id is empty');
    }
    if (!terminalKey) {
        throw new GatewayProtocolError('terminal_key is empty');
    }

    const envelope = await sendRequest(
        input,
        {
            request_id: nextRequestId('send-key'),
            command: 'send-key',
            auth_token: authToken,
            terminal_id: terminalId,
            terminal_key: terminalKey,
            expected_generation: input.expectedGeneration,
        },
    );
    return parseTerminalMutationResult(envelope);
}

export function subscribeToGatewayEvents(input: GatewayConnection & {
    authToken: string;
    sinceSequence: number;
    eventLimit?: number;
    onEnvelope: (envelope: GatewayEnvelope) => void;
    onError?: (error: Error) => void;
}): () => void {
    const authToken = input.authToken.trim();
    if (!authToken) {
        throw new GatewayProtocolError('Auth token is empty');
    }

    const openVariant = (connection: GatewayConnection) => {
        const socket = new WebSocket(resolveGatewaySocketUrl({
            transportMode: connection.transportMode === 'relay' ? 'relay' : 'lan',
            host: connection.host,
            port: connection.port,
            publicEndpoint: connection.publicEndpoint,
            transportSharedSecret: connection.transportSharedSecret,
        }));
        return socket;
    };
    let closedByClient = false;
    let settled = false;
    let attemptedRelayFallback = false;
    let socket = openVariant(input);
    let activeConnection: GatewayConnection = input;

    const finalizeWithError = (error: GatewayProtocolError) => {
        if (closedByClient || settled) {
            return;
        }
        settled = true;
        input.onError?.(error);
    };

    const bindSocket = (connection: GatewayConnection) => {
        const boundSocket = socket;

        socket.onopen = () => {
            if (boundSocket !== socket) {
                return;
            }
            const request: GatewayRequest = {
                request_id: nextRequestId('subscribe'),
                command: 'events.subscribe',
                auth_token: authToken,
                since_sequence: Math.max(0, Math.trunc(input.sinceSequence)),
                event_limit: input.eventLimit ?? 128,
            };
            if (usesEncryptedGatewayTransport(connection)) {
                void encodeEncryptedGatewayRequest({
                    request: request as unknown as Record<string, unknown>,
                    authToken,
                    transportSharedSecret: connection.transportSharedSecret!.trim(),
                }).then((encryptedRequest) => {
                    socket.send(JSON.stringify(encryptedRequest));
                }).catch((error) => {
                    finalizeWithError(error instanceof Error ? error : new GatewayProtocolError('Failed to encrypt gateway subscription request'));
                    socket.close();
                });
                return;
            }
            socket.send(JSON.stringify(request));
        };

        socket.onmessage = async (event) => {
            if (boundSocket !== socket) {
                return;
            }
            try {
                const rawText = typeof event.data === 'string' ? event.data : String(event.data ?? '');
                const envelope = await parseReceivedEnvelope(rawText, connection);
                if (envelope.status === 'error') {
                    const error = new GatewayProtocolError(
                        envelope.error_message ?? envelope.error_code ?? 'Gateway rejected subscription',
                        envelope.error_code,
                    );
                    finalizeWithError(error);
                    socket.close();
                    return;
                }
                input.onEnvelope(envelope);
            } catch (error) {
                finalizeWithError(
                    error instanceof GatewayProtocolError
                        ? error
                        : new GatewayProtocolError(
                            error instanceof Error ? error.message : 'Invalid subscription payload',
                        ),
                );
                socket.close();
            }
        };

        socket.onerror = () => {
            if (boundSocket !== socket) {
                return;
            }
            const relayConnection = !attemptedRelayFallback ? relayFallbackConnection(activeConnection) : null;
            if (relayConnection) {
                attemptedRelayFallback = true;
                activeConnection = relayConnection;
                socket = openVariant(relayConnection);
                bindSocket(relayConnection);
                return;
            }
            finalizeWithError(new GatewayProtocolError('Gateway subscription socket failed'));
        };

        socket.onclose = (event) => {
            if (boundSocket !== socket) {
                return;
            }
            if (closedByClient || settled) {
                return;
            }
            if (event.code === 1000) {
                return;
            }
            const relayConnection = !attemptedRelayFallback ? relayFallbackConnection(activeConnection) : null;
            if (relayConnection) {
                attemptedRelayFallback = true;
                activeConnection = relayConnection;
                socket = openVariant(relayConnection);
                bindSocket(relayConnection);
                return;
            }
            finalizeWithError(new GatewayProtocolError(
                event.reason || `Gateway subscription closed unexpectedly (code ${event.code})`,
            ));
        };
    };

    bindSocket(activeConnection);

    return () => {
        closedByClient = true;
        settled = true;
        socket.close();
    };
}
