import { describe, expect, it } from 'vitest';

import type {
    TerminalReadResult,
    TerminalSemanticDefaultReadResult,
    TerminalSnapshotV2Result,
    TerminalStreamChunkRecord,
} from './types';
import {
    applyTerminalDelta,
    accumulateTerminalStreamAckBytes,
    mapTerminalSemanticDefaultToAutomationRead,
    mapSnapshotV2ToTerminalReadResult,
    mapTerminalStreamChunkToTerminalReadResult,
    resolveTerminalStreamAckRetryDelay,
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

function makeTerminalSnapshotV2Result(
    overrides: Partial<TerminalSnapshotV2Result> = {},
): TerminalSnapshotV2Result {
    return {
        terminalId: 'terminal-1',
        generation: 2,
        scope: 'visible',
        snapshotFormat: 'ansi_text',
        capturedAt: '2026-03-29T00:00:00Z',
        cacheAgeMs: 8,
        frameId: 'frm_2',
        parentFrameId: 'frm_1',
        content: 'A\nB\nC',
        ...overrides,
    };
}

function makeTerminalStreamChunkRecord(
    overrides: Partial<TerminalStreamChunkRecord> = {},
): TerminalStreamChunkRecord {
    return {
        streamKind: 'terminal_chunk',
        streamId: 'stream-1',
        terminalId: 'terminal-1',
        generation: 3,
        frameId: 'frm_3',
        parentFrameId: 'frm_2',
        deltaKind: 'reset',
        content: 'A\nB\nC\nD\nE',
        contentLength: 9,
        changedRows: [],
        ...overrides,
    };
}

function makeTerminalSemanticDefaultReadResult(
    overrides: Partial<TerminalSemanticDefaultReadResult> = {},
): TerminalSemanticDefaultReadResult {
    return {
        kind: 'semantic',
        result: {
            terminalId: 'terminal-1',
            generation: 12,
            scope: 'visible',
            extractedAt: '2026-03-29T04:00:00Z',
            logicalLines: ['$ ls', 'README.md'],
            exactText: '$ ls\nREADME.md',
            promptDetected: true,
        },
        ...overrides,
    } as TerminalSemanticDefaultReadResult;
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

    it('maps v2 snapshot payloads into terminal read compatibility shape', () => {
        const mapped = mapSnapshotV2ToTerminalReadResult(
            makeTerminalSnapshotV2Result({
                terminalId: 'terminal-2',
                generation: 4,
                scope: 'screen',
                frameId: 'frm_9',
                parentFrameId: 'frm_8',
                content: 'OK\nDONE',
            }),
            null,
        );

        expect(mapped).toMatchObject({
            terminalId: 'terminal-2',
            generation: 4,
            scope: 'screen',
            mode: 'snapshot',
            contentKind: 'snapshot',
            frameId: 'frm_9',
            parentFrameId: 'frm_8',
            content: 'OK\nDONE',
            totalLines: 2,
            returnedLines: 2,
            truncated: false,
            hasChanges: true,
            deltaKind: 'reset',
        });
    });

    it('marks hasChanges=false when v2 snapshot frame id is unchanged', () => {
        const previous = makeTerminalReadResult({
            terminalId: 'terminal-1',
            frameId: 'frm_2',
            content: 'A\nB\nC',
        });
        const mapped = mapSnapshotV2ToTerminalReadResult(
            makeTerminalSnapshotV2Result({
                terminalId: 'terminal-1',
                frameId: 'frm_2',
                content: 'A\nB\nC',
            }),
            previous,
        );

        expect(mapped.hasChanges).toBe(false);
        expect(mapped.deltaKind).toBe('none');
    });

    it('maps terminal stream reset chunk into snapshot compatibility result', () => {
        const mapped = mapTerminalStreamChunkToTerminalReadResult(
            makeTerminalStreamChunkRecord({
                terminalId: 'terminal-2',
                generation: 7,
                deltaKind: 'reset',
                frameId: 'frm_10',
                parentFrameId: 'frm_9',
                content: 'READY\n$',
                changedRows: [],
            }),
            null,
        );

        expect(mapped).toMatchObject({
            terminalId: 'terminal-2',
            generation: 7,
            mode: 'snapshot',
            contentKind: 'snapshot',
            frameId: 'frm_10',
            parentFrameId: 'frm_9',
            hasChanges: true,
            deltaKind: 'reset',
            changedRows: [],
            content: 'READY\n$',
        });
    });

    it('maps terminal stream row chunk into merge-safe delta compatibility result', () => {
        const mapped = mapTerminalStreamChunkToTerminalReadResult(
            makeTerminalStreamChunkRecord({
                deltaKind: 'rows',
                frameId: 'frm_4',
                parentFrameId: 'frm_3',
                content: '[line 3] DONE',
                changedRows: [{ index: 3, kind: 'update', text: 'DONE' }],
            }),
            makeTerminalReadResult({
                terminalId: 'terminal-1',
                frameId: 'frm_3',
                content: 'A\nB\nC\nOLD',
            }),
        );
        expect(mapped).not.toBeNull();
        if (!mapped) {
            throw new Error('expected mapped stream delta result');
        }

        expect(mapped.mode).toBe('delta');
        expect(mapped.contentKind).toBe('delta');
        expect(mapped.deltaKind).toBe('rows');
        expect(mapped.hasChanges).toBe(true);
        expect(mapped.changedRows).toEqual([{ index: 3, kind: 'update', text: 'DONE' }]);
    });

    it('accumulates terminal stream ack bytes and signals when batch threshold is reached', () => {
        expect(accumulateTerminalStreamAckBytes({
            pendingBytes: 0,
            incomingBytes: 200,
            batchBytes: 512,
        })).toEqual({
            pendingBytes: 200,
            shouldFlush: false,
        });

        expect(accumulateTerminalStreamAckBytes({
            pendingBytes: 380,
            incomingBytes: 160,
            batchBytes: 512,
        })).toEqual({
            pendingBytes: 540,
            shouldFlush: true,
        });
    });

    it('maps semantic-default result into automation read shape without command branching', () => {
        const mapped = mapTerminalSemanticDefaultToAutomationRead(makeTerminalSemanticDefaultReadResult());

        expect(mapped).toEqual({
            source: 'semantic',
            terminalId: 'terminal-1',
            generation: 12,
            scope: 'visible',
            extractedAt: '2026-03-29T04:00:00Z',
            promptDetected: true,
            lines: ['$ ls', 'README.md'],
            text: '$ ls\nREADME.md',
        });
    });

    it('maps semantic fallback snapshot into the same automation read shape', () => {
        const mapped = mapTerminalSemanticDefaultToAutomationRead(
            makeTerminalSemanticDefaultReadResult({
                kind: 'snapshot',
                result: {
                    terminalId: 'terminal-1',
                    generation: 13,
                    scope: 'visible',
                    snapshotFormat: 'ansi_text',
                    capturedAt: '2026-03-29T04:01:00Z',
                    cacheAgeMs: 2,
                    frameId: 'frm_20',
                    parentFrameId: 'frm_19',
                    content: 'line1\nline2',
                },
            }),
        );

        expect(mapped).toEqual({
            source: 'snapshot',
            terminalId: 'terminal-1',
            generation: 13,
            scope: 'visible',
            extractedAt: '2026-03-29T04:01:00Z',
            promptDetected: null,
            lines: ['line1', 'line2'],
            text: 'line1\nline2',
        });
    });

    it('computes bounded terminal stream ack retry delay and cuts off beyond budget', () => {
        expect(resolveTerminalStreamAckRetryDelay({
            attempt: 1,
            elapsedMs: 0,
            maxAttempts: 6,
            maxWindowMs: 6_000,
            baseDelayMs: 120,
            maxDelayMs: 1_000,
        })).toBe(120);

        expect(resolveTerminalStreamAckRetryDelay({
            attempt: 4,
            elapsedMs: 1_200,
            maxAttempts: 6,
            maxWindowMs: 6_000,
            baseDelayMs: 120,
            maxDelayMs: 1_000,
        })).toBe(960);

        expect(resolveTerminalStreamAckRetryDelay({
            attempt: 7,
            elapsedMs: 1_400,
            maxAttempts: 6,
            maxWindowMs: 6_000,
            baseDelayMs: 120,
            maxDelayMs: 1_000,
        })).toBeNull();

        expect(resolveTerminalStreamAckRetryDelay({
            attempt: 2,
            elapsedMs: 6_500,
            maxAttempts: 6,
            maxWindowMs: 6_000,
            baseDelayMs: 120,
            maxDelayMs: 1_000,
        })).toBeNull();
    });
});
