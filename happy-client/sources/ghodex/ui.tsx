import { Ionicons } from '@expo/vector-icons';
import * as React from 'react';
import { ActivityIndicator, Pressable, Text, View } from 'react-native';
import { StyleSheet, useUnistyles } from 'react-native-unistyles';

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
    const { theme } = useUnistyles();

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
                <ActivityIndicator color={kind === 'secondary' ? theme.colors.text : theme.colors.button.primary.tint} />
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
    const { theme } = useUnistyles();

    return (
        <View style={styles.infoPill}>
            <Ionicons color={theme.colors.button.primary.background} name={icon} size={14} />
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

const styles = StyleSheet.create((theme) => ({
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
        backgroundColor: theme.colors.button.primary.background,
    },
    secondaryButton: {
        backgroundColor: theme.colors.surfaceHigh,
        borderWidth: 1,
        borderColor: theme.colors.divider,
    },
    buttonPressed: {
        opacity: 0.88,
    },
    buttonDisabled: {
        opacity: 0.65,
    },
    primaryButtonText: {
        color: theme.colors.button.primary.tint,
        fontSize: 15,
        fontWeight: '700',
    },
    secondaryButtonText: {
        color: theme.colors.text,
        fontSize: 15,
        fontWeight: '700',
    },
    card: {
        backgroundColor: theme.colors.surface,
        borderRadius: 20,
        padding: 16,
        gap: 12,
        borderWidth: 1,
        borderColor: theme.colors.divider,
    },
    cardTitle: {
        color: theme.colors.text,
        fontSize: 18,
        fontWeight: '700',
    },
    cardSubtitle: {
        color: theme.colors.textSecondary,
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
        backgroundColor: theme.colors.surfaceHigh,
        borderWidth: 1,
        borderColor: theme.colors.divider,
    },
    infoPillText: {
        color: theme.colors.text,
        fontSize: 12,
        fontWeight: '700',
    },
    metaRow: {
        gap: 4,
    },
    metaLabel: {
        color: theme.colors.groupped.sectionTitle,
        fontSize: 12,
        fontWeight: '700',
        textTransform: 'uppercase',
        letterSpacing: 0.6,
    },
    metaValue: {
        color: theme.colors.text,
        fontSize: 14,
        lineHeight: 20,
    },
    monoText: {
        fontFamily: 'monospace',
    },
}));
