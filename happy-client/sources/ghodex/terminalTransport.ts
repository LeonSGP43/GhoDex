import type { TerminalChangedRow, TerminalReadResult } from './types';

type TerminalDeltaBaseView = Pick<TerminalReadResult, 'terminalId' | 'frameId' | 'truncated'>;

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
