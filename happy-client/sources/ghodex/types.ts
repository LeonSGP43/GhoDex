export interface GatewayConnection {
    host: string;
    port: number;
    transportMode?: 'lan' | 'relay';
    publicEndpoint?: string | null;
    transportSharedSecret?: string | null;
}

export interface GatewayEnvelope {
    request_id?: string;
    status?: string;
    error_code?: string;
    error_message?: string;
    transport_mode?: string;
    encrypted_payload?: string;
    result?: Record<string, unknown>;
    event?: string;
    sequence?: number;
    resource?: {
        type?: string;
        id?: string;
        generation?: number;
    };
    gap?: boolean;
    requires_snapshot_resync?: boolean;
    payload?: Record<string, unknown>;
}

export interface PairingBeginResult {
    pairingCode: string;
    client: string | null;
    scopes: string[];
}

export interface PairingExchangeResult {
    authToken: string;
    tokenId: string | null;
    scopes: string[];
    desktopId: string | null;
    desktopLabel: string | null;
    preferredDesktopId: string | null;
    transportMode: string | null;
    publicEndpoint: string | null;
    transportSharedSecret: string | null;
}

export interface TerminalRow {
    tabId: string;
    terminalId: string;
    generation: number;
    title: string | null;
    workingDirectory: string | null;
    focused: boolean;
    visible: boolean;
}

export interface TabRow {
    tabId: string;
    generation: number;
    windowNumber: number;
    title: string | null;
    focused: boolean;
    isMainWindow: boolean;
    hasBell: boolean;
    terminals: TerminalRow[];
}

export interface SnapshotResult {
    protocolVersion: string | null;
    lastSequence: number;
    tabs: TabRow[];
    terminals: TerminalRow[];
}

export interface TerminalReadResult {
    terminalId: string;
    generation: number;
    scope: string;
    mode: string;
    contentKind: string;
    consistency: string;
    capturedAt: string | null;
    cacheAgeMs: number;
    lastSequence: number;
    frameId: string | null;
    parentFrameId: string | null;
    hasChanges: boolean;
    deltaKind: string | null;
    deltaText: string | null;
    changedRows: TerminalChangedRow[];
    totalLines: number;
    returnedLines: number;
    truncated: boolean;
    nextCursor: string | null;
    observedWriteId: string | null;
    readAfterReady: boolean | null;
    content: string;
}

export interface TerminalChangedRow {
    index: number;
    kind: string;
    text: string | null;
}

export interface TerminalMutationResult {
    terminalId: string;
    generation: number;
    sequence: number;
    operation: string | null;
    acknowledged: boolean;
    writeId: string | null;
}

export interface TabMutationResult {
    tabId: string;
    generation: number;
    sequence: number;
    terminalId: string | null;
    terminalGeneration: number | null;
    title: string | null;
    closed: boolean;
    requiresConfirmation: boolean;
    confirmationTitle: string | null;
    confirmationMessage: string | null;
}
