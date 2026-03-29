export interface TerminalControlKeySpec {
    id: string;
    label: string;
    payload: string;
    terminalKey?: string;
}

export type MobileTerminalInputMode = 'simple' | 'realtime';

export type TerminalSubmitMutation =
    | { kind: 'run-command'; commandText: string }
    | { kind: 'send-text'; text: string };

export const TERMINAL_CONTROL_KEYS: readonly TerminalControlKeySpec[] = [
    { id: 'backspace', label: '⌫', payload: '\u007F', terminalKey: 'backspace' },
    { id: 'enter', label: 'Enter', payload: '\r', terminalKey: 'enter' },
    { id: 'ctrl_c', label: 'Ctrl+C', payload: '\u0003', terminalKey: 'ctrl_c' },
    { id: 'ctrl_d', label: 'Ctrl+D', payload: '\u0004', terminalKey: 'ctrl_d' },
    { id: 'esc', label: 'Esc', payload: '\u001B', terminalKey: 'escape' },
    { id: 'tab', label: 'Tab', payload: '\t', terminalKey: 'tab' },
    { id: 'up', label: '↑', payload: '\u001B[A', terminalKey: 'arrow_up' },
    { id: 'down', label: '↓', payload: '\u001B[B', terminalKey: 'arrow_down' },
];

export function normalizeCommandInput(input: string): string {
    return input
        .replace(/\r\n?/g, '\n')
        .replace(/[\u2028\u2029]/g, '\n');
}

export function shouldPasteRawInput(input: string): boolean {
    const trimmed = normalizeCommandInput(input).trim();
    return trimmed.includes('\n');
}

export function buildTerminalTextPayload(input: string): string | null {
    const normalized = normalizeCommandInput(input);
    if (!normalized.trim()) {
        return null;
    }

    if (shouldPasteRawInput(normalized)) {
        return normalized;
    }

    return `${normalized}\r`;
}

export function resolveTerminalSubmitMutation(
    input: string,
    mode: MobileTerminalInputMode,
): TerminalSubmitMutation | null {
    const normalized = normalizeCommandInput(input);
    if (!normalized.trim()) {
        return null;
    }

    if (mode === 'simple') {
        if (shouldPasteRawInput(normalized)) {
            return {
                kind: 'send-text',
                text: normalized,
            };
        }
        return {
            kind: 'run-command',
            commandText: normalized.trim(),
        };
    }

    const payload = buildTerminalTextPayload(normalized);
    if (!payload) {
        return null;
    }
    return {
        kind: 'send-text',
        text: payload,
    };
}

export function resolveRealtimeKeyPayload(key: string): string | null {
    if (key === 'Enter') {
        return '\r';
    }
    if (key === 'Backspace') {
        return '\u007F';
    }
    if (key === 'Tab') {
        return '\t';
    }
    if (typeof key === 'string' && key.length === 1) {
        return key;
    }
    return null;
}

function commonPrefixLength(left: string, right: string): number {
    const limit = Math.min(left.length, right.length);
    let index = 0;
    while (index < limit && left[index] === right[index]) {
        index += 1;
    }
    return index;
}

interface RealtimeInputDeltaOptions {
    previousDraft: string;
    nextDraft: string;
    keypressBackspacesPending: number;
    backspaceKeypressHint?: boolean;
}

export interface RealtimeInputDeltaResult {
    emittedText: string;
    nextDraft: string;
    remainingKeypressBackspaces: number;
}

export function deriveRealtimeInputDelta(options: RealtimeInputDeltaOptions): RealtimeInputDeltaResult {
    const previousDraft = options.previousDraft;
    const nextDraft = options.nextDraft;
    const pendingBackspaces = Math.max(0, Math.floor(options.keypressBackspacesPending));
    const backspaceKeypressHint = options.backspaceKeypressHint === true;

    if (previousDraft === nextDraft) {
        return {
            emittedText: '',
            nextDraft,
            remainingKeypressBackspaces: pendingBackspaces,
        };
    }

    const prefix = commonPrefixLength(previousDraft, nextDraft);
    let previousSuffixStart = previousDraft.length;
    let nextSuffixStart = nextDraft.length;
    while (
        previousSuffixStart > prefix
        && nextSuffixStart > prefix
        && previousDraft[previousSuffixStart - 1] === nextDraft[nextSuffixStart - 1]
    ) {
        previousSuffixStart -= 1;
        nextSuffixStart -= 1;
    }

    const deletedCount = Math.max(0, previousSuffixStart - prefix);
    const insertedText = nextDraft.slice(prefix, nextSuffixStart);
    const suppressedDeletes = Math.min(deletedCount, pendingBackspaces);
    const effectiveDeletedCount = deletedCount - suppressedDeletes;

    if (
        (pendingBackspaces > 0 || backspaceKeypressHint)
        && deletedCount === 0
        && insertedText.length > 0
        && insertedText.trim().length === 0
    ) {
        // Some Android IMEs can emit a whitespace text delta immediately after
        // Backspace keypress in tiny/hidden capture inputs. Ignore that
        // synthetic insertion and consume one pending keypress backspace.
        return {
            emittedText: '',
            nextDraft: previousDraft,
            remainingKeypressBackspaces: Math.max(0, pendingBackspaces - 1),
        };
    }

    return {
        emittedText: `${'\u007F'.repeat(effectiveDeletedCount)}${insertedText}`,
        nextDraft,
        remainingKeypressBackspaces: pendingBackspaces - suppressedDeletes,
    };
}

export function appendLatencySample(
    samples: readonly number[],
    sampleMs: number,
    maxSamples = 20,
): number[] {
    if (!Number.isFinite(sampleMs) || sampleMs <= 0) {
        return [...samples];
    }

    const clampedMaxSamples = Math.max(1, Math.floor(maxSamples));
    const rounded = Math.round(sampleMs);
    const next = [...samples, rounded];
    if (next.length <= clampedMaxSamples) {
        return next;
    }
    return next.slice(next.length - clampedMaxSamples);
}

export function applyRealtimeLocalEchoPayload(current: string, payload: string): string {
    let next = current;
    const chars = Array.from(payload);
    for (const char of chars) {
        if (char === '\u007F') {
            const currentChars = Array.from(next);
            currentChars.pop();
            next = currentChars.join('');
            continue;
        }

        if (char === '\r' || char === '\n') {
            next = '';
            continue;
        }

        if (char === '\t') {
            next += '\t';
            continue;
        }

        const code = char.charCodeAt(0);
        if (code < 0x20 || code === 0x7F) {
            continue;
        }
        next += char;
    }

    const MAX_PREVIEW_CHARS = 256;
    if (Array.from(next).length > MAX_PREVIEW_CHARS) {
        return Array.from(next).slice(-MAX_PREVIEW_CHARS).join('');
    }
    return next;
}

export function shouldDeferRealtimeLiveRead(input: {
    isRealtimeInputMode: boolean;
    writeInFlight: boolean;
    bufferedInputLength: number;
    flushTimerActive: boolean;
}): boolean {
    if (!input.isRealtimeInputMode) {
        return false;
    }

    return input.writeInFlight
        || input.bufferedInputLength > 0
        || input.flushTimerActive;
}

export function resolveRealtimeMutationRetryDelayMs(retries: number): number {
    const safeRetries = Math.max(0, Math.floor(retries));
    return 40 + (safeRetries * 30);
}

export function summarizeLatency(samples: readonly number[]): {
    lastMs: number | null;
    avgMs: number | null;
} {
    if (!samples.length) {
        return {
            lastMs: null,
            avgMs: null,
        };
    }

    const total = samples.reduce((sum, item) => sum + item, 0);
    return {
        lastMs: samples[samples.length - 1] ?? null,
        avgMs: Math.round(total / samples.length),
    };
}

function encodeTerminalDebugChar(char: string): string {
    if (char === '\r') {
        return '<CR>';
    }
    if (char === '\n') {
        return '<LF>';
    }
    if (char === '\t') {
        return '<TAB>';
    }
    if (char === '\u007F') {
        return '<DEL>';
    }
    if (char === ' ') {
        return '<SP>';
    }

    const code = char.charCodeAt(0);
    if (code >= 0x20 && code < 0x7F) {
        return char;
    }

    if (code <= 0xFF) {
        return `<0x${code.toString(16).toUpperCase().padStart(2, '0')}>`;
    }
    return `<U+${code.toString(16).toUpperCase().padStart(4, '0')}>`;
}

export function describeTerminalDebugText(value: string, maxChars = 24): string {
    const safeMaxChars = Math.max(1, Math.floor(maxChars));
    const chars = Array.from(value);
    const visibleChars = chars.slice(0, safeMaxChars);
    const clipped = chars.length > visibleChars.length;
    const preview = visibleChars.map((char) => encodeTerminalDebugChar(char)).join('');
    return `${preview}${clipped ? '...' : ''} (len=${chars.length})`;
}
