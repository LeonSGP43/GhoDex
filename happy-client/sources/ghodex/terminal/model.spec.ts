import { describe, expect, it, vi } from 'vitest';

import {
    applyTerminalRowDelta,
    buildTerminalRows,
    parseAnsiRow,
    type TerminalRenderRow,
} from './model';

function rowsToContent(rows: TerminalRenderRow[]): string {
    return rows.map((row) => row.raw).join('\n');
}

describe('terminal row model', () => {
    it('parses one ANSI row without losing the original text content', () => {
        const row = parseAnsiRow('\u001b[31mERR\u001b[0m ok');

        expect(row.raw).toBe('\u001b[31mERR\u001b[0m ok');
        expect(row.plainText).toBe('ERR ok');
        expect(row.segments.map((segment) => segment.text).join('')).toBe('ERR ok');
        expect(row.segments[0]?.style.color).toBeDefined();
    });

    it('builds rows from snapshot content line by line', () => {
        const rows = buildTerminalRows('one\ntwo\nthree');

        expect(rows).toHaveLength(3);
        expect(rows.map((row) => row.plainText)).toEqual(['one', 'two', 'three']);
        expect(rowsToContent(rows)).toBe('one\ntwo\nthree');
    });

    it('reparses only touched rows during delta updates', () => {
        const originalRows = buildTerminalRows('A\nB\nC');
        const parseRow = vi.fn((line: string) => parseAnsiRow(line));

        const nextRows = applyTerminalRowDelta(
            originalRows,
            [
                { index: 1, kind: 'update', text: '\u001b[32mB!\u001b[0m' },
                { index: 3, kind: 'insert', text: 'D' },
            ],
            parseRow,
        );

        expect(nextRows).not.toBeNull();
        expect(parseRow).toHaveBeenCalledTimes(2);
        expect(nextRows?.[0]).toBe(originalRows[0]);
        expect(nextRows?.[2]).toBe(originalRows[2]);
        expect(rowsToContent(nextRows ?? [])).toBe('A\n\u001b[32mB!\u001b[0m\nC\nD');
    });

    it('applies mixed update and delete row patches deterministically', () => {
        const nextRows = applyTerminalRowDelta(
            buildTerminalRows('A\nB\nC\nD'),
            [
                { index: 1, kind: 'update', text: 'D' },
                { index: 2, kind: 'delete', text: null },
                { index: 3, kind: 'delete', text: null },
            ],
        );

        expect(nextRows).not.toBeNull();
        expect(rowsToContent(nextRows ?? [])).toBe('A\nD');
        expect(nextRows?.map((row) => row.plainText)).toEqual(['A', 'D']);
    });

    it('rejects unsupported row patch kinds', () => {
        const nextRows = applyTerminalRowDelta(
            buildTerminalRows('A'),
            [{ index: 0, kind: 'replace-all', text: 'B' }],
        );

        expect(nextRows).toBeNull();
    });
});
