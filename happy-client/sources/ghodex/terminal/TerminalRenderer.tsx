import * as React from 'react';
import { FlatList, Text, View } from 'react-native';
import { StyleSheet, useUnistyles } from 'react-native-unistyles';

import type { TerminalRenderRow } from './model';

export function TerminalRenderer({
    rows,
    optimisticInput,
    renderMode = 'terminal',
    showOptimisticCursor = false,
}: {
    rows: TerminalRenderRow[];
    optimisticInput?: string;
    renderMode?: 'terminal' | 'text';
    showOptimisticCursor?: boolean;
}) {
    const { theme } = useUnistyles();
    const renderRows = React.useMemo(() => {
        if (rows.length > 0) {
            return rows;
        }
        if (!(optimisticInput || showOptimisticCursor)) {
            return rows;
        }
        return [{ raw: '', plainText: '', segments: [{ style: {}, text: '' }] }];
    }, [optimisticInput, rows, showOptimisticCursor]);
    const rowCount = renderRows.length;
    const textOnlyMode = renderMode === 'text';
    const listRef = React.useRef<FlatList<TerminalRenderRow> | null>(null);

    const scrollToBottom = React.useCallback(() => {
        requestAnimationFrame(() => {
            listRef.current?.scrollToEnd({ animated: false });
        });
    }, []);

    React.useEffect(() => {
        scrollToBottom();
    }, [optimisticInput, rowCount, scrollToBottom, showOptimisticCursor]);

    const renderItem = React.useCallback(({ item, index }: { item: TerminalRenderRow; index: number }) => (
        <View style={styles.row}>
            <Text selectable style={[styles.rowText, { color: theme.colors.terminal.stdout }]}>
                {textOnlyMode
                    ? item.plainText
                    : item.segments.map((segment, segmentIndex) => (
                        <Text
                            key={`${segmentIndex}-${segment.text.length}`}
                            style={{
                                color: segment.style.color ?? theme.colors.terminal.stdout,
                                backgroundColor: segment.style.backgroundColor,
                                fontWeight: segment.style.fontWeight,
                            }}
                        >
                            {segment.text}
                        </Text>
                    ))}
                {index === rowCount - 1 && (optimisticInput || showOptimisticCursor) ? (
                    <Text style={[styles.optimisticText, { color: theme.colors.terminal.stdout }]}>
                        {`${optimisticInput ?? ''}${showOptimisticCursor ? '|' : ''}`}
                    </Text>
                ) : null}
            </Text>
        </View>
    ), [optimisticInput, rowCount, showOptimisticCursor, textOnlyMode, theme.colors.terminal.stdout]);

    return (
        <FlatList
            contentContainerStyle={styles.content}
            data={renderRows}
            initialNumToRender={60}
            keyExtractor={(_, index) => String(index)}
            onContentSizeChange={scrollToBottom}
            ref={listRef}
            removeClippedSubviews
            renderItem={renderItem}
            style={styles.list}
            windowSize={8}
        />
    );
}

const styles = StyleSheet.create(() => ({
    list: {
        flex: 1,
    },
    content: {
        paddingHorizontal: 12,
        paddingVertical: 10,
    },
    row: {
        minHeight: 20,
    },
    rowText: {
        fontSize: 13,
        lineHeight: 20,
        fontFamily: 'monospace',
    },
    optimisticText: {
        opacity: 0.85,
    },
}));
