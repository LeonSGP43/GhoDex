import * as React from 'react';
import { Text } from 'react-native';

import { buildTerminalRows } from './terminal/model';

const DEFAULT_FOREGROUND = '#f8efe3';

export function renderAnsiText(content: string): React.ReactNode {
    const rows = buildTerminalRows(content);
    return rows.map((row, index) => (
        <Text key={`ansi-line-${index}`} style={{ color: DEFAULT_FOREGROUND }}>
            {row.segments.map((segment, segmentIndex) => (
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
            {index < rows.length - 1 ? '\n' : ''}
        </Text>
    ));
}
