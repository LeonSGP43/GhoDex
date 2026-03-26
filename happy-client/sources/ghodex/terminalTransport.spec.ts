import { describe, expect, it } from 'vitest';

import type { TerminalReadResult } from './types';
import {
    applyTerminalDelta,
    shouldFallbackToTerminalSnapshot,
    shouldRequestTerminalDelta,
} from './terminalTransport';

function makeTerminalReadResult(overrides: Partial<TerminalReadResult> = {}): TerminalReadResult {
    return {
        terminalId: 'terminal-1',
        generation: 1,
        scope: 'visible',
        mode: 'snapshot',
        contentKind: 'snapshot',
        consistency: 'fresh_visible',
        capturedAt: null,
        cacheAgeMs: 0,
        lastSequence: 0,
        frameId: 'frm_1',
        parentFrameId: null,
        hasChanges: false,
        deltaKind: null,
        deltaText: null,
        changedRows: [],
        totalLines: 4,
        returnedLines: 4,
        truncated: false,
        nextCursor: null,
        observedWriteId: null,
        readAfterReady: null,
        content: 'A\nB\nC\nD',
        ...overrides,
    };
}

describe('terminal transport helpers', () => {
    it('applies mixed update and delete rows deterministically', () => {
        const merged = applyTerminalDelta('A\nB\nC\nD', [
            { index: 1, kind: 'update', text: 'D' },
            { index: 2, kind: 'delete', text: null },
            { index: 3, kind: 'delete', text: null },
        ]);

        expect(merged).toBe('A\nD');
    });

    it('disables delta requests when the current local buffer is truncated', () => {
        expect(shouldRequestTerminalDelta(
            makeTerminalReadResult({
                terminalId: 'terminal-1',
                frameId: 'frm_truncated',
                truncated: true,
            }),
            'terminal-1',
        )).toBe(false);
    });

    it('allows delta requests only for the same terminal with a retained frame id', () => {
        expect(shouldRequestTerminalDelta(
            makeTerminalReadResult({
                terminalId: 'terminal-1',
                frameId: 'frm_safe',
                truncated: false,
            }),
            'terminal-1',
        )).toBe(true);

        expect(shouldRequestTerminalDelta(
            makeTerminalReadResult({
                terminalId: 'terminal-1',
                frameId: 'frm_safe',
                truncated: false,
            }),
            'terminal-2',
        )).toBe(false);
    });

    it('forces snapshot fallback when returned delta lineage does not match the requested base frame', () => {
        expect(shouldFallbackToTerminalSnapshot({
            requestMode: 'delta',
            requestedSinceFrameId: 'frm_base',
            currentView: makeTerminalReadResult({
                terminalId: 'terminal-1',
                frameId: 'frm_base',
                truncated: false,
            }),
            result: makeTerminalReadResult({
                terminalId: 'terminal-1',
                mode: 'delta',
                contentKind: 'delta',
                frameId: 'frm_new',
                parentFrameId: 'frm_other',
                hasChanges: true,
                changedRows: [{ index: 4, kind: 'insert', text: 'E' }],
            }),
        })).toBe(true);
    });

    it('forces snapshot fallback when a changed delta carries no safe row patch', () => {
        expect(shouldFallbackToTerminalSnapshot({
            requestMode: 'delta',
            requestedSinceFrameId: 'frm_base',
            currentView: makeTerminalReadResult({
                terminalId: 'terminal-1',
                frameId: 'frm_base',
                truncated: false,
            }),
            result: makeTerminalReadResult({
                terminalId: 'terminal-1',
                mode: 'delta',
                contentKind: 'delta',
                frameId: 'frm_new',
                parentFrameId: 'frm_base',
                hasChanges: true,
                changedRows: [],
            }),
        })).toBe(true);
    });
});
