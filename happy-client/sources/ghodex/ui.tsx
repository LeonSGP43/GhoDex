import { Ionicons } from '@expo/vector-icons';
import * as React from 'react';
import { ActivityIndicator, Pressable, StyleSheet, Text, View } from 'react-native';

export function ActionButton({
    busy,
    compact,
    kind = 'primary',
    label,
    onPress,
}: {
    busy?: boolean;
    compact?: boolean;
    kind?: 'primary' | 'secondary';
    label: string;
    onPress: () => void;
}) {
    return (
        <Pressable
            disabled={busy}
            onPress={onPress}
            style={({ pressed }) => [
                styles.button,
                compact ? styles.buttonCompact : null,
                kind === 'secondary' ? styles.secondaryButton : styles.primaryButton,
                pressed ? styles.buttonPressed : null,
                busy ? styles.buttonDisabled : null,
            ]}
        >
            {busy ? (
                <ActivityIndicator color={kind === 'secondary' ? '#4e4337' : '#fffaf3'} />
            ) : (
                <Text style={kind === 'secondary' ? styles.secondaryButtonText : styles.primaryButtonText}>{label}</Text>
            )}
        </Pressable>
    );
}

export function SurfaceCard({
    children,
    title,
    subtitle,
}: {
    children: React.ReactNode;
    title?: string;
    subtitle?: string;
}) {
    return (
        <View style={styles.card}>
            {title ? <Text style={styles.cardTitle}>{title}</Text> : null}
            {subtitle ? <Text style={styles.cardSubtitle}>{subtitle}</Text> : null}
            {children}
        </View>
    );
}

export function InfoPill({
    icon,
    label,
}: {
    icon: keyof typeof Ionicons.glyphMap;
    label: string;
}) {
    return (
        <View style={styles.infoPill}>
            <Ionicons color="#8a4b2a" name={icon} size={14} />
            <Text style={styles.infoPillText}>{label}</Text>
        </View>
    );
}

export function SectionValue({
    label,
    mono = false,
    value,
}: {
    label: string;
    mono?: boolean;
    value: string;
}) {
    return (
        <View style={styles.metaRow}>
            <Text style={styles.metaLabel}>{label}</Text>
            <Text style={[styles.metaValue, mono ? styles.monoText : null]}>{value}</Text>
        </View>
    );
}

const styles = StyleSheet.create({
    button: {
        flex: 1,
        minHeight: 48,
        borderRadius: 14,
        alignItems: 'center',
        justifyContent: 'center',
        paddingHorizontal: 12,
    },
    buttonCompact: {
        minHeight: 40,
        borderRadius: 12,
        paddingHorizontal: 14,
    },
    primaryButton: {
        backgroundColor: '#8a4b2a',
    },
    secondaryButton: {
        backgroundColor: '#ede2d5',
    },
    buttonPressed: {
        opacity: 0.88,
    },
    buttonDisabled: {
        opacity: 0.65,
    },
    primaryButtonText: {
        color: '#fffaf3',
        fontSize: 15,
        fontWeight: '700',
    },
    secondaryButtonText: {
        color: '#4e4337',
        fontSize: 15,
        fontWeight: '700',
    },
    card: {
        backgroundColor: '#fbf7f0',
        borderRadius: 20,
        padding: 16,
        gap: 12,
        borderWidth: 1,
        borderColor: '#e8ddd0',
    },
    cardTitle: {
        color: '#241d17',
        fontSize: 18,
        fontWeight: '700',
    },
    cardSubtitle: {
        color: '#6b6259',
        fontSize: 13,
        lineHeight: 19,
    },
    infoPill: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: 6,
        paddingHorizontal: 10,
        paddingVertical: 8,
        borderRadius: 999,
        backgroundColor: '#efe4d8',
    },
    infoPillText: {
        color: '#5c4b3c',
        fontSize: 12,
        fontWeight: '700',
    },
    metaRow: {
        gap: 4,
    },
    metaLabel: {
        color: '#6a5f53',
        fontSize: 12,
        fontWeight: '700',
        textTransform: 'uppercase',
        letterSpacing: 0.6,
    },
    metaValue: {
        color: '#261f18',
        fontSize: 14,
        lineHeight: 20,
    },
    monoText: {
        fontFamily: 'monospace',
    },
});
