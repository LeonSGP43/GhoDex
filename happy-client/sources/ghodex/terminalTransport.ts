import type {
    TerminalChangedRow,
    TerminalReadResult,
    TerminalSnapshotV2Result,
    TerminalStreamChunkRecord,
} from './types';

type TerminalDeltaBaseView = Pick<TerminalReadResult, 'terminalId' | 'frameId' | 'truncated'>;
type TerminalStreamBaseView = Pick<TerminalReadResult, 'terminalId' | 'frameId' | 'content' | 'lastSequence'>;

interface TerminalStreamAckAccumulatorInput {
    pendingBytes: number;
    incomingBytes: number;
    batchBytes: number;
}

export function applyTerminalDelta(content: string, changedRows: TerminalChangedRow[]): string | null {
    if (changedRows.length === 0) {
        return content;
    }

    const nextLines = content.split('\n');
    const deletes = changedRows
        .filter((row) => row.kind === 'delete')
        .sort((left, right) => right.index - left.index);
    const updates = changedRows
        .filter((row) => row.kind === 'update')
        .sort((left, right) => left.index - right.index);
    const inserts = changedRows
        .filter((row) => row.kind === 'insert')
        .sort((left, right) => left.index - right.index);
    const unsupported = changedRows.some((row) => !['delete', 'update', 'insert'].includes(row.kind));

    if (unsupported) {
        return null;
    }

    // Deletes use original row indexes, so they must run from bottom to top.
    for (const row of deletes) {
        if (row.index < nextLines.length) {
            nextLines.splice(row.index, 1);
        }
    }

    for (const row of updates) {
        while (nextLines.length <= row.index) {
            nextLines.push('');
        }
        nextLines[row.index] = row.text ?? '';
    }

    for (const row of inserts) {
        while (nextLines.length < row.index) {
            nextLines.push('');
        }
        nextLines.splice(row.index, 0, row.text ?? '');
    }

    return nextLines.join('\n');
}

export function shouldRequestTerminalDelta(
    currentView: TerminalDeltaBaseView | null,
    terminalId: string,
): boolean {
    return !!(
        currentView
        && currentView.terminalId === terminalId
        && currentView.frameId
        && !currentView.truncated
    );
}

export function shouldFallbackToTerminalSnapshot(input: {
    requestMode: 'snapshot' | 'delta';
    requestedSinceFrameId?: string;
    currentView: TerminalDeltaBaseView | null;
    result: Pick<TerminalReadResult, 'terminalId' | 'frameId' | 'parentFrameId' | 'hasChanges' | 'changedRows'>;
}): boolean {
    if (input.requestMode !== 'delta') {
        return false;
    }

    if (input.currentView?.truncated) {
        return true;
    }

    if (!input.requestedSinceFrameId || input.currentView?.terminalId !== input.result.terminalId) {
        return true;
    }

    const lineageMatches = input.result.parentFrameId === input.requestedSinceFrameId
        || (!input.result.hasChanges && input.result.frameId === input.requestedSinceFrameId);

    return !lineageMatches || (input.result.hasChanges && input.result.changedRows.length === 0);
}

export function mapSnapshotV2ToTerminalReadResult(
    snapshot: TerminalSnapshotV2Result,
    previous: Pick<TerminalReadResult, 'terminalId' | 'frameId'> | null,
): TerminalReadResult {
    const splitLines = snapshot.content.split('\n');
    const totalLines = snapshot.content.length === 0 ? 0 : splitLines.length;
    const frameChanged = !previous
        || previous.terminalId !== snapshot.terminalId
        || previous.frameId !== snapshot.frameId;
    const hasChanges = frameChanged;

    return {
        terminalId: snapshot.terminalId,
        generation: snapshot.generation,
        scope: snapshot.scope,
        mode: 'snapshot',
        contentKind: 'snapshot',
        consistency: `fresh_${snapshot.scope}`,
        capturedAt: snapshot.capturedAt,
        cacheAgeMs: snapshot.cacheAgeMs,
        lastSequence: 0,
        frameId: snapshot.frameId,
        parentFrameId: snapshot.parentFrameId,
        hasChanges,
        deltaKind: hasChanges ? 'reset' : 'none',
        deltaText: hasChanges ? snapshot.content : null,
        changedRows: [],
        totalLines,
        returnedLines: totalLines,
        truncated: false,
        nextCursor: null,
        observedWriteId: null,
        readAfterReady: null,
        content: snapshot.content,
    };
}

function countTerminalLines(content: string): number {
    if (!content) {
        return 0;
    }
    return content.split('\n').length;
}

function streamChunkHasFrameChange(
    chunk: TerminalStreamChunkRecord,
    previous: TerminalStreamBaseView | null,
): boolean {
    return !previous
        || previous.terminalId !== chunk.terminalId
        || previous.frameId !== chunk.frameId;
}

export function mapTerminalStreamChunkToTerminalReadResult(
    chunk: TerminalStreamChunkRecord,
    previous: TerminalStreamBaseView | null,
): TerminalReadResult | null {
    const isSnapshotLike = chunk.deltaKind === 'reset' || chunk.deltaKind === 'snapshot';

    if (isSnapshotLike) {
        const totalLines = countTerminalLines(chunk.content);
        return {
            terminalId: chunk.terminalId,
            generation: chunk.generation,
            scope: 'visible',
            mode: 'snapshot',
            contentKind: 'snapshot',
            consistency: 'stream_live',
            capturedAt: null,
            cacheAgeMs: 0,
            lastSequence: previous?.lastSequence ?? 0,
            frameId: chunk.frameId,
            parentFrameId: chunk.parentFrameId,
            hasChanges: streamChunkHasFrameChange(chunk, previous),
            deltaKind: chunk.deltaKind,
            deltaText: chunk.content,
            changedRows: [],
            totalLines,
            returnedLines: totalLines,
            truncated: false,
            nextCursor: null,
            observedWriteId: null,
            readAfterReady: null,
            content: chunk.content,
        };
    }

    if (!previous || previous.terminalId !== chunk.terminalId) {
        return null;
    }

    if (
        chunk.parentFrameId
        && previous.frameId
        && chunk.parentFrameId !== previous.frameId
        && chunk.frameId !== previous.frameId
    ) {
        return null;
    }

    if (!chunk.changedRows.length) {
        const unchangedFrame = chunk.frameId === previous.frameId;
        if (!unchangedFrame) {
            return null;
        }
        const totalLines = countTerminalLines(previous.content);
        return {
            terminalId: chunk.terminalId,
            generation: chunk.generation,
            scope: 'visible',
            mode: 'delta',
            contentKind: 'delta',
            consistency: 'stream_live',
            capturedAt: null,
            cacheAgeMs: 0,
            lastSequence: previous.lastSequence,
            frameId: chunk.frameId,
            parentFrameId: chunk.parentFrameId,
            hasChanges: false,
            deltaKind: chunk.deltaKind,
            deltaText: chunk.content || null,
            changedRows: [],
            totalLines,
            returnedLines: totalLines,
            truncated: false,
            nextCursor: null,
            observedWriteId: null,
            readAfterReady: null,
            content: previous.content,
        };
    }

    const merged = applyTerminalDelta(previous.content, chunk.changedRows);
    if (merged === null) {
        return null;
    }

    const totalLines = countTerminalLines(merged);
    return {
        terminalId: chunk.terminalId,
        generation: chunk.generation,
        scope: 'visible',
        mode: 'delta',
        contentKind: 'delta',
        consistency: 'stream_live',
        capturedAt: null,
        cacheAgeMs: 0,
        lastSequence: previous.lastSequence,
        frameId: chunk.frameId,
        parentFrameId: chunk.parentFrameId,
        hasChanges: true,
        deltaKind: chunk.deltaKind,
        deltaText: chunk.content || null,
        changedRows: chunk.changedRows,
        totalLines,
        returnedLines: totalLines,
        truncated: false,
        nextCursor: null,
        observedWriteId: null,
        readAfterReady: null,
        content: merged,
    };
}

export function accumulateTerminalStreamAckBytes(
    input: TerminalStreamAckAccumulatorInput,
): { pendingBytes: number; shouldFlush: boolean } {
    const pendingBytes = Math.max(0, Math.trunc(input.pendingBytes));
    const incomingBytes = Math.max(0, Math.trunc(input.incomingBytes));
    const batchBytes = Math.max(1, Math.trunc(input.batchBytes));
    const nextPendingBytes = pendingBytes + incomingBytes;
    return {
        pendingBytes: nextPendingBytes,
        shouldFlush: nextPendingBytes >= batchBytes,
    };
}
