import { describe, expect, it } from 'vitest';

import {
    applyRealtimeLocalEchoPayload,
    appendLatencySample,
    buildTerminalTextPayload,
    describeTerminalDebugText,
    deriveRealtimeInputDelta,
    normalizeCommandInput,
    resolveRealtimeMutationRetryDelayMs,
    resolveRealtimeKeyPayload,
    resolveTerminalSubmitMutation,
    shouldDeferRealtimeLiveRead,
    shouldPasteRawInput,
    summarizeLatency,
    TERMINAL_CONTROL_KEYS,
} from './terminalInput';

describe('terminal input helpers', () => {
    it('normalizes line separators and identifies raw multiline text', () => {
        const normalized = normalizeCommandInput('echo hi\r\necho there\u2028done');

        expect(normalized).toBe('echo hi\necho there\ndone');
        expect(shouldPasteRawInput(normalized)).toBe(true);
    });

    it('builds tty payload with enter for single-line input', () => {
        expect(buildTerminalTextPayload('ls -la')).toBe('ls -la\r');
    });

    it('keeps multiline payload raw without forced enter suffix', () => {
        expect(buildTerminalTextPayload('line1\nline2')).toBe('line1\nline2');
    });

    it('returns null for blank input payload', () => {
        expect(buildTerminalTextPayload('   \n  ')).toBeNull();
    });

    it('routes simple single-line submit to run-command so send means execute', () => {
        expect(resolveTerminalSubmitMutation('ls -la', 'simple')).toEqual({
            kind: 'run-command',
            commandText: 'ls -la',
        });
    });

    it('routes simple multiline submit to raw send-text payload', () => {
        expect(resolveTerminalSubmitMutation('echo a\necho b', 'simple')).toEqual({
            kind: 'send-text',
            text: 'echo a\necho b',
        });
    });

    it('routes realtime submit to tty send-text payload with enter suffix for single line', () => {
        expect(resolveTerminalSubmitMutation('pwd', 'realtime')).toEqual({
            kind: 'send-text',
            text: 'pwd\r',
        });
    });

    it('maps realtime key payloads with shell-friendly backspace behavior', () => {
        expect(resolveRealtimeKeyPayload('Backspace')).toBe('\u007F');
        expect(resolveRealtimeKeyPayload('Enter')).toBe('\r');
        expect(resolveRealtimeKeyPayload('Tab')).toBe('\t');
        expect(resolveRealtimeKeyPayload('x')).toBe('x');
        expect(resolveRealtimeKeyPayload('Shift')).toBeNull();
    });

    it('derives realtime insert/delete payloads from input change deltas', () => {
        expect(deriveRealtimeInputDelta({
            previousDraft: 'hel',
            nextDraft: 'hello',
            keypressBackspacesPending: 0,
        })).toEqual({
            emittedText: 'lo',
            nextDraft: 'hello',
            remainingKeypressBackspaces: 0,
        });

        expect(deriveRealtimeInputDelta({
            previousDraft: 'hello',
            nextDraft: 'hel',
            keypressBackspacesPending: 0,
        })).toEqual({
            emittedText: '\u007F\u007F',
            nextDraft: 'hel',
            remainingKeypressBackspaces: 0,
        });
    });

    it('suppresses duplicate deletes already emitted by realtime keypress path', () => {
        expect(deriveRealtimeInputDelta({
            previousDraft: 'hello',
            nextDraft: 'hell',
            keypressBackspacesPending: 1,
        })).toEqual({
            emittedText: '',
            nextDraft: 'hell',
            remainingKeypressBackspaces: 0,
        });
    });

    it('ignores synthetic whitespace insertion after keypress backspace on Android IME', () => {
        expect(deriveRealtimeInputDelta({
            previousDraft: 'hello',
            nextDraft: 'hello ',
            keypressBackspacesPending: 1,
        })).toEqual({
            emittedText: '',
            nextDraft: 'hello',
            remainingKeypressBackspaces: 0,
        });
    });

    it('ignores synthetic whitespace insertion when Android reports backspace without delete delta', () => {
        expect(deriveRealtimeInputDelta({
            previousDraft: '',
            nextDraft: ' ',
            keypressBackspacesPending: 0,
            backspaceKeypressHint: true,
        })).toEqual({
            emittedText: '',
            nextDraft: '',
            remainingKeypressBackspaces: 0,
        });
    });

    it('exposes control key payloads including ctrl and arrows', () => {
        expect(TERMINAL_CONTROL_KEYS).toEqual(expect.arrayContaining([
            expect.objectContaining({ id: 'backspace', payload: '\u007F', terminalKey: 'backspace' }),
            expect.objectContaining({ id: 'ctrl_c', payload: '\u0003', terminalKey: 'ctrl_c' }),
            expect.objectContaining({ id: 'enter', payload: '\r', terminalKey: 'enter' }),
            expect.objectContaining({ id: 'up', payload: '\u001B[A', terminalKey: 'arrow_up' }),
        ]));
    });
});

describe('latency helpers', () => {
    it('retains only the latest N samples', () => {
        const samples = [100, 120, 130];
        expect(appendLatencySample(samples, 140, 3)).toEqual([120, 130, 140]);
    });

    it('ignores invalid latency samples', () => {
        expect(appendLatencySample([100, 120], Number.NaN, 4)).toEqual([100, 120]);
    });

    it('summarizes last and average latency', () => {
        expect(summarizeLatency([100, 120, 140])).toEqual({ lastMs: 140, avgMs: 120 });
        expect(summarizeLatency([])).toEqual({ lastMs: null, avgMs: null });
    });

    it('defers realtime live read only when write or input buffer is active', () => {
        expect(shouldDeferRealtimeLiveRead({
            isRealtimeInputMode: false,
            writeInFlight: true,
            bufferedInputLength: 10,
            flushTimerActive: true,
        })).toBe(false);

        expect(shouldDeferRealtimeLiveRead({
            isRealtimeInputMode: true,
            writeInFlight: false,
            bufferedInputLength: 0,
            flushTimerActive: false,
        })).toBe(false);

        expect(shouldDeferRealtimeLiveRead({
            isRealtimeInputMode: true,
            writeInFlight: true,
            bufferedInputLength: 0,
            flushTimerActive: false,
        })).toBe(true);

        expect(shouldDeferRealtimeLiveRead({
            isRealtimeInputMode: true,
            writeInFlight: false,
            bufferedInputLength: 1,
            flushTimerActive: false,
        })).toBe(true);
    });

    it('computes bounded retry delay for realtime mutation queue', () => {
        expect(resolveRealtimeMutationRetryDelayMs(0)).toBe(40);
        expect(resolveRealtimeMutationRetryDelayMs(1)).toBe(70);
        expect(resolveRealtimeMutationRetryDelayMs(3.8)).toBe(130);
        expect(resolveRealtimeMutationRetryDelayMs(-2)).toBe(40);
    });
});

describe('realtime local echo', () => {
    it('appends printable chars and trims on backspace', () => {
        let preview = '';
        preview = applyRealtimeLocalEchoPayload(preview, 'abc');
        expect(preview).toBe('abc');
        preview = applyRealtimeLocalEchoPayload(preview, '\u007F');
        expect(preview).toBe('ab');
    });

    it('resets preview line on enter and keeps tab', () => {
        let preview = applyRealtimeLocalEchoPayload('', 'ls');
        expect(preview).toBe('ls');
        preview = applyRealtimeLocalEchoPayload(preview, '\t');
        expect(preview).toBe('ls\t');
        preview = applyRealtimeLocalEchoPayload(preview, '\r');
        expect(preview).toBe('');
    });

    it('ignores non-printable control chars', () => {
        const preview = applyRealtimeLocalEchoPayload('ab', '\u0001\u0002');
        expect(preview).toBe('ab');
    });
});

describe('debug text formatter', () => {
    it('renders terminal control chars and spaces as readable markers', () => {
        expect(describeTerminalDebugText('a \r\n\t\u007F')).toBe('a<SP><CR><LF><TAB><DEL> (len=6)');
    });

    it('clips long values and keeps original character count', () => {
        expect(describeTerminalDebugText('abcdef', 4)).toBe('abcd... (len=6)');
    });
});
