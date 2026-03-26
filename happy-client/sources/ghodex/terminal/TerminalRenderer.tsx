import * as React from 'react';
import { FlatList, Text, View } from 'react-native';
import { StyleSheet, useUnistyles } from 'react-native-unistyles';

import type { TerminalRenderRow } from './model';

export function TerminalRenderer({
    rows,
}: {
    rows: TerminalRenderRow[];
}) {
    const { theme } = useUnistyles();

    const renderItem = React.useCallback(({ item }: { item: TerminalRenderRow }) => (
        <View style={styles.row}>
            <Text selectable style={[styles.rowText, { color: theme.colors.terminal.stdout }]}>
                {item.segments.map((segment, index) => (
                    <Text
                        key={`${index}-${segment.text.length}`}
                        style={{
                            color: segment.style.color ?? theme.colors.terminal.stdout,
                            backgroundColor: segment.style.backgroundColor,
                            fontWeight: segment.style.fontWeight,
                        }}
                    >
                        {segment.text}
                    </Text>
                ))}
            </Text>
        </View>
    ), [theme.colors.terminal.stdout]);

    return (
        <FlatList
            contentContainerStyle={styles.content}
            data={rows}
            initialNumToRender={60}
            keyExtractor={(_, index) => String(index)}
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
}));
