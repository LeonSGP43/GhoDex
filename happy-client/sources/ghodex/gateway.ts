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
    TerminalRow,
} from './types';

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
    requested_scopes?: string[];
    pairing_code?: string;
    tab_id?: string;
    parent_tab_id?: string;
    terminal_id?: string;
    scope?: string;
    mode?: string;
    command_text?: string;
    text?: string;
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

function buildGatewayUrl(connection: GatewayConnection): string {
    const trimmedHost = connection.host.trim() || '127.0.0.1';
    const host = trimmedHost.includes(':') && !trimmedHost.startsWith('[') ? `[${trimmedHost}]` : trimmedHost;
    return `ws://${host}:${connection.port}`;
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

async function sendRequest(connection: GatewayConnection, request: GatewayRequest): Promise<GatewayEnvelope> {
    const url = buildGatewayUrl(connection);

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
            socket.send(JSON.stringify(request));
        };

        socket.onmessage = (event) => {
            if (settled) {
                return;
            }
            settled = true;
            cleanup();
            socket.close();

            try {
                const rawText = typeof event.data === 'string' ? event.data : String(event.data ?? '');
                const envelope = parseEnvelope(rawText);
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
    requestedScopes?: readonly string[];
}): Promise<PairingBeginResult> {
    const envelope = await sendRequest(
        input,
        {
            request_id: nextRequestId('pair-begin'),
            command: 'gateway.pairing.begin',
            client: input.client,
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

    const socket = new WebSocket(buildGatewayUrl(input));
    let closedByClient = false;
    let settled = false;

    const finalizeWithError = (error: GatewayProtocolError) => {
        if (closedByClient || settled) {
            return;
        }
        settled = true;
        input.onError?.(error);
    };

    socket.onopen = () => {
        const request: GatewayRequest = {
            request_id: nextRequestId('subscribe'),
            command: 'events.subscribe',
            auth_token: authToken,
            since_sequence: Math.max(0, Math.trunc(input.sinceSequence)),
            event_limit: input.eventLimit ?? 128,
        };
        socket.send(JSON.stringify(request));
    };

    socket.onmessage = (event) => {
        try {
            const rawText = typeof event.data === 'string' ? event.data : String(event.data ?? '');
            const envelope = parseEnvelope(rawText);
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
        finalizeWithError(new GatewayProtocolError('Gateway subscription socket failed'));
    };

    socket.onclose = (event) => {
        if (closedByClient || settled) {
            return;
        }
        if (event.code === 1000) {
            return;
        }
        finalizeWithError(new GatewayProtocolError(
            event.reason || `Gateway subscription closed unexpectedly (code ${event.code})`,
        ));
    };

    return () => {
        closedByClient = true;
        settled = true;
        socket.close();
    };
}
