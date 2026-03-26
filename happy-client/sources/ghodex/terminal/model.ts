import type { TextStyle } from 'react-native';

import type { TerminalChangedRow } from '../types';

export type TerminalAnsiState = {
    color?: string;
    backgroundColor?: string;
    fontWeight?: TextStyle['fontWeight'];
};

export type TerminalSegment = {
    style: TerminalAnsiState;
    text: string;
};

export type TerminalRenderRow = {
    raw: string;
    plainText: string;
    segments: TerminalSegment[];
};

const ESC = '\u001b';
const ANSI_16_COLORS = [
    '#1d2021',
    '#cc241d',
    '#98971a',
    '#d79921',
    '#458588',
    '#b16286',
    '#689d6a',
    '#ebdbb2',
    '#928374',
    '#fb4934',
    '#b8bb26',
    '#fabd2f',
    '#83a598',
    '#d3869b',
    '#8ec07c',
    '#fbf1c7',
] as const;

function cloneState(state: TerminalAnsiState): TerminalAnsiState {
    return {
        color: state.color,
        backgroundColor: state.backgroundColor,
        fontWeight: state.fontWeight,
    };
}

function pushSegment(segments: TerminalSegment[], state: TerminalAnsiState, text: string) {
    if (!text) {
        return;
    }

    const previous = segments[segments.length - 1];
    if (
        previous
        && previous.style.color === state.color
        && previous.style.backgroundColor === state.backgroundColor
        && previous.style.fontWeight === state.fontWeight
    ) {
        previous.text += text;
        return;
    }

    segments.push({ style: cloneState(state), text });
}

function rgb(r: number, g: number, b: number): string {
    return `rgb(${r}, ${g}, ${b})`;
}

function parseColor256(index: number): string {
    if (index < 16) {
        return ANSI_16_COLORS[index] ?? ANSI_16_COLORS[7];
    }
    if (index >= 16 && index <= 231) {
        const value = index - 16;
        const r = Math.floor(value / 36);
        const g = Math.floor((value % 36) / 6);
        const b = value % 6;
        const map = [0, 95, 135, 175, 215, 255];
        return rgb(map[r] ?? 0, map[g] ?? 0, map[b] ?? 0);
    }

    const gray = 8 + (index - 232) * 10;
    return rgb(gray, gray, gray);
}

function applySgr(state: TerminalAnsiState, params: number[]) {
    const values = params.length === 0 ? [0] : params;
    for (let i = 0; i < values.length; i += 1) {
        const value = values[i];
        switch (value) {
        case 0:
            state.color = undefined;
            state.backgroundColor = undefined;
            state.fontWeight = undefined;
            break;
        case 1:
            state.fontWeight = '700';
            break;
        case 22:
            state.fontWeight = undefined;
            break;
        case 39:
            state.color = undefined;
            break;
        case 49:
            state.backgroundColor = undefined;
            break;
        default:
            if (value >= 30 && value <= 37) {
                state.color = ANSI_16_COLORS[value - 30];
                break;
            }
            if (value >= 90 && value <= 97) {
                state.color = ANSI_16_COLORS[8 + (value - 90)];
                break;
            }
            if (value >= 40 && value <= 47) {
                state.backgroundColor = ANSI_16_COLORS[value - 40];
                break;
            }
            if (value >= 100 && value <= 107) {
                state.backgroundColor = ANSI_16_COLORS[8 + (value - 100)];
                break;
            }
            if ((value === 38 || value === 48) && i + 1 < values.length) {
                const target = value === 38 ? 'color' : 'backgroundColor';
                const mode = values[i + 1];
                if (mode === 5 && i + 2 < values.length) {
                    state[target] = parseColor256(values[i + 2] ?? 15);
                    i += 2;
                    break;
                }
                if (mode === 2 && i + 4 < values.length) {
                    state[target] = rgb(values[i + 2] ?? 0, values[i + 3] ?? 0, values[i + 4] ?? 0);
                    i += 4;
                }
            }
            break;
        }
    }
}

export function parseAnsiRow(line: string): TerminalRenderRow {
    if (!line.includes(ESC)) {
        return {
            raw: line,
            plainText: line,
            segments: [{ style: {}, text: line }],
        };
    }

    const segments: TerminalSegment[] = [];
    const state: TerminalAnsiState = {};
    let cursor = 0;

    while (cursor < line.length) {
        const escIndex = line.indexOf(ESC, cursor);
        if (escIndex === -1) {
            pushSegment(segments, state, line.slice(cursor));
            break;
        }

        pushSegment(segments, state, line.slice(cursor, escIndex));

        const match = /^\u001b\[([0-9;]*)m/.exec(line.slice(escIndex));
        if (!match) {
            cursor = escIndex + 1;
            continue;
        }

        const params = match[1]
            ? match[1]
                .split(';')
                .map((item) => Number.parseInt(item, 10))
                .filter((item) => Number.isFinite(item))
            : [];
        applySgr(state, params);
        cursor = escIndex + match[0].length;
    }

    const normalizedSegments = segments.length > 0 ? segments : [{ style: {}, text: line }];
    return {
        raw: line,
        plainText: normalizedSegments.map((segment) => segment.text).join(''),
        segments: normalizedSegments,
    };
}

export function buildTerminalRows(content: string): TerminalRenderRow[] {
    return content.split('\n').map(parseAnsiRow);
}

export function applyTerminalRowDelta(
    rows: TerminalRenderRow[],
    changedRows: TerminalChangedRow[],
    parseRow: (line: string) => TerminalRenderRow = parseAnsiRow,
): TerminalRenderRow[] | null {
    const unsupported = changedRows.some((row) => !['delete', 'update', 'insert'].includes(row.kind));
    if (unsupported) {
        return null;
    }

    const nextRows = [...rows];
    const deletes = changedRows
        .filter((row) => row.kind === 'delete')
        .sort((left, right) => right.index - left.index);
    const updates = changedRows
        .filter((row) => row.kind === 'update')
        .sort((left, right) => left.index - right.index);
    const inserts = changedRows
        .filter((row) => row.kind === 'insert')
        .sort((left, right) => left.index - right.index);

    for (const row of deletes) {
        if (row.index < nextRows.length) {
            nextRows.splice(row.index, 1);
        }
    }

    for (const row of updates) {
        while (nextRows.length <= row.index) {
            nextRows.push(parseRow(''));
        }
        nextRows[row.index] = parseRow(row.text ?? '');
    }

    for (const row of inserts) {
        while (nextRows.length < row.index) {
            nextRows.push(parseRow(''));
        }
        nextRows.splice(row.index, 0, parseRow(row.text ?? ''));
    }

    return nextRows;
}
