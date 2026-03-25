import * as React from 'react';
import { Text, type TextStyle } from 'react-native';

type AnsiState = {
    color?: string;
    backgroundColor?: string;
    fontWeight?: TextStyle['fontWeight'];
};

type Segment = {
    style: AnsiState;
    text: string;
};

const ESC = '\u001b';
const DEFAULT_FOREGROUND = '#f8efe3';
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

function cloneState(state: AnsiState): AnsiState {
    return {
        color: state.color,
        backgroundColor: state.backgroundColor,
        fontWeight: state.fontWeight,
    };
}

function pushSegment(segments: Segment[], state: AnsiState, text: string) {
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

function parseColor256(index: number): string {
    if (index < 16) {
        return ANSI_16_COLORS[index] ?? DEFAULT_FOREGROUND;
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

function rgb(r: number, g: number, b: number): string {
    return `rgb(${r}, ${g}, ${b})`;
}

function applySgr(state: AnsiState, params: number[]) {
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

function parseAnsiLine(line: string): Segment[] {
    if (!line.includes(ESC)) {
        return [{ style: {}, text: line }];
    }

    const segments: Segment[] = [];
    const state: AnsiState = {};
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
            ? match[1].split(';').map((item) => Number.parseInt(item, 10)).filter((item) => Number.isFinite(item))
            : [];
        applySgr(state, params);
        cursor = escIndex + match[0].length;
    }

    return segments.length > 0 ? segments : [{ style: {}, text: line }];
}

export function renderAnsiText(content: string): React.ReactNode {
    const lines = content.split('\n');
    return lines.map((line, index) => {
        const segments = parseAnsiLine(line);
        return (
            <Text key={`ansi-line-${index}`} style={{ color: DEFAULT_FOREGROUND }}>
                {segments.map((segment, segmentIndex) => (
                    <Text
                        key={`ansi-segment-${index}-${segmentIndex}`}
                        style={{
                            color: segment.style.color ?? DEFAULT_FOREGROUND,
                            backgroundColor: segment.style.backgroundColor,
                            fontWeight: segment.style.fontWeight,
                        }}
                    >
                        {segment.text}
                    </Text>
                ))}
                {index < lines.length - 1 ? '\n' : ''}
            </Text>
        );
    });
}

