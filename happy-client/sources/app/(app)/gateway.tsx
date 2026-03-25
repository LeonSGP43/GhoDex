import * as React from 'react';
import { ActivityIndicator, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { useRouter } from 'expo-router';
import { useFocusEffect } from '@react-navigation/native';
import { clearStoredSession, loadStoredSession, saveStoredSession, type StoredSession } from '@/ghodex/storage';
import { INITIAL_GATEWAY_SESSION, POLL_INTERVAL_OPTIONS, sanitizePollInterval, sanitizePort } from '@/ghodex/sessionState';
import { ActionButton, InfoPill, SectionValue, SurfaceCard } from '@/ghodex/ui';

export default function GhoDexGatewayScreen() {
    const router = useRouter();
    const [loaded, setLoaded] = React.useState(false);
    const [session, setSession] = React.useState<StoredSession>(INITIAL_GATEWAY_SESSION);
    const [host, setHost] = React.useState(INITIAL_GATEWAY_SESSION.host);
    const [portText, setPortText] = React.useState(String(INITIAL_GATEWAY_SESSION.port));
    const [liveUpdatesEnabled, setLiveUpdatesEnabled] = React.useState(INITIAL_GATEWAY_SESSION.liveUpdatesEnabled);
    const [pollIntervalMs, setPollIntervalMs] = React.useState(INITIAL_GATEWAY_SESSION.pollIntervalMs);

    useFocusEffect(React.useCallback(() => {
        let active = true;
        void (async () => {
            const stored = await loadStoredSession();
            if (!active) {
                return;
            }
            setSession(stored);
            setHost(stored.host);
            setPortText(String(stored.port));
            setLiveUpdatesEnabled(stored.liveUpdatesEnabled);
            setPollIntervalMs(stored.pollIntervalMs);
            setLoaded(true);
        })();

        return () => {
            active = false;
        };
    }, []));

    const resolvedPort = sanitizePort(portText);
    const paired = !!session.authToken.trim();

    const handleApply = React.useCallback(async () => {
        const current = await loadStoredSession();
        const nextSession = {
            ...current,
            host: host.trim() || INITIAL_GATEWAY_SESSION.host,
            port: resolvedPort,
            liveUpdatesEnabled,
            pollIntervalMs: sanitizePollInterval(pollIntervalMs),
        };
        await saveStoredSession(nextSession);
        setSession(nextSession);
        router.replace('/');
    }, [host, liveUpdatesEnabled, pollIntervalMs, resolvedPort, router]);

    const handleClear = React.useCallback(async () => {
        await clearStoredSession();
        router.replace('/');
    }, [router]);

    if (!loaded) {
        return (
            <View style={styles.loadingScreen}>
                <ActivityIndicator size="large" color="#8a4b2a" />
                <Text style={styles.loadingText}>Loading settings…</Text>
            </View>
        );
    }

    return (
        <ScrollView style={styles.screen} contentContainerStyle={styles.content}>
            <SurfaceCard title="Settings" subtitle="Connection, pairing status, and reset actions stay here. The workspace stays focused on the terminal only.">
                <View style={styles.pillRow}>
                    <InfoPill icon="radio-outline" label={`${host || INITIAL_GATEWAY_SESSION.host}:${resolvedPort}`} />
                    <InfoPill icon="key-outline" label={paired ? 'Paired' : 'Unpaired'} />
                </View>
            </SurfaceCard>

            <SurfaceCard title="Gateway Endpoint" subtitle="Use 127.0.0.1 with adb reverse, or the desktop LAN IP when the phone connects directly.">
                <TextInput
                    autoCapitalize="none"
                    autoCorrect={false}
                    onChangeText={setHost}
                    placeholder="127.0.0.1"
                    placeholderTextColor="#8f867a"
                    style={styles.input}
                    value={host}
                />
                <TextInput
                    autoCapitalize="none"
                    autoCorrect={false}
                    inputMode="numeric"
                    keyboardType="number-pad"
                    onChangeText={setPortText}
                    placeholder="19527"
                    placeholderTextColor="#8f867a"
                    style={styles.input}
                    value={portText}
                />
                <SectionValue label="Resolved port" mono value={String(resolvedPort)} />
                <View style={styles.actions}>
                    <ActionButton label="Save And Return" onPress={handleApply} />
                </View>
            </SurfaceCard>

            <SurfaceCard title="Display Sync" subtitle="Realtime uses the gateway subscription stream. Polling stays available for debugging or battery-sensitive cases.">
                <View style={styles.optionRow}>
                    <Pressable
                        onPress={() => setLiveUpdatesEnabled(true)}
                        style={({ pressed }) => [
                            styles.optionChip,
                            liveUpdatesEnabled ? styles.optionChipActive : null,
                            pressed ? styles.optionChipPressed : null,
                        ]}
                    >
                        <Text style={[styles.optionChipText, liveUpdatesEnabled ? styles.optionChipTextActive : null]}>
                            Realtime Stream
                        </Text>
                    </Pressable>
                    <Pressable
                        onPress={() => setLiveUpdatesEnabled(false)}
                        style={({ pressed }) => [
                            styles.optionChip,
                            !liveUpdatesEnabled ? styles.optionChipActive : null,
                            pressed ? styles.optionChipPressed : null,
                        ]}
                    >
                        <Text style={[styles.optionChipText, !liveUpdatesEnabled ? styles.optionChipTextActive : null]}>
                            Polling Only
                        </Text>
                    </Pressable>
                </View>

                <SectionValue
                    label="Current sync"
                    value={liveUpdatesEnabled ? 'Subscription stream for active terminal' : 'Timer-based polling only'}
                />

                <Text style={styles.optionLabel}>Fallback / polling interval</Text>
                <View style={styles.optionRow}>
                    {POLL_INTERVAL_OPTIONS.map((value) => (
                        <Pressable
                            key={value}
                            onPress={() => setPollIntervalMs(value)}
                            style={({ pressed }) => [
                                styles.intervalChip,
                                pollIntervalMs === value ? styles.intervalChipActive : null,
                                pressed ? styles.optionChipPressed : null,
                            ]}
                        >
                            <Text style={[styles.intervalChipText, pollIntervalMs === value ? styles.intervalChipTextActive : null]}>
                                {value}ms
                            </Text>
                        </Pressable>
                    ))}
                </View>
            </SurfaceCard>

            <SurfaceCard title="Authorization" subtitle="Handle QR pairing here when you need to bind or replace the phone session.">
                <SectionValue label="Token" mono value={paired ? 'issued' : 'not issued'} />
                <SectionValue label="Token id" mono value={session.tokenId || 'not issued yet'} />
                <SectionValue label="Scopes" mono value={session.scopes.length ? session.scopes.join(', ') : 'none'} />
                <View style={styles.actions}>
                    <ActionButton label={paired ? 'Re-open Pairing' : 'Open Pairing'} onPress={() => router.push('/pairing')} />
                </View>
            </SurfaceCard>

            <SurfaceCard title="Reset" subtitle="Clear the saved mobile-side session if you want to fully re-pair this phone.">
                <View style={styles.actions}>
                    <ActionButton kind="secondary" label="Clear Saved Session" onPress={handleClear} />
                </View>
            </SurfaceCard>
        </ScrollView>
    );
}

const styles = StyleSheet.create({
    screen: {
        flex: 1,
        backgroundColor: '#f4efe6',
    },
    content: {
        padding: 16,
        gap: 16,
    },
    loadingScreen: {
        flex: 1,
        alignItems: 'center',
        justifyContent: 'center',
        gap: 12,
        backgroundColor: '#f4efe6',
    },
    loadingText: {
        color: '#43352a',
        fontSize: 16,
    },
    pillRow: {
        flexDirection: 'row',
        flexWrap: 'wrap',
        gap: 8,
    },
    input: {
        backgroundColor: '#fffdf8',
        borderWidth: 1,
        borderColor: '#ded2c4',
        borderRadius: 14,
        paddingHorizontal: 14,
        paddingVertical: 12,
        color: '#2a221b',
        fontSize: 16,
    },
    actions: {
        flexDirection: 'row',
        gap: 12,
    },
    optionLabel: {
        color: '#6a5f53',
        fontSize: 12,
        fontWeight: '700',
        textTransform: 'uppercase',
        letterSpacing: 0.6,
    },
    optionRow: {
        flexDirection: 'row',
        flexWrap: 'wrap',
        gap: 10,
    },
    optionChip: {
        borderRadius: 14,
        paddingHorizontal: 14,
        paddingVertical: 11,
        backgroundColor: '#ede2d5',
    },
    optionChipActive: {
        backgroundColor: '#8a4b2a',
    },
    optionChipPressed: {
        opacity: 0.84,
    },
    optionChipText: {
        color: '#4e4337',
        fontSize: 14,
        fontWeight: '700',
    },
    optionChipTextActive: {
        color: '#fff8ef',
    },
    intervalChip: {
        borderRadius: 999,
        paddingHorizontal: 12,
        paddingVertical: 9,
        backgroundColor: '#fffaf4',
        borderWidth: 1,
        borderColor: '#ded2c4',
    },
    intervalChipActive: {
        backgroundColor: '#1f1a16',
        borderColor: '#1f1a16',
    },
    intervalChipText: {
        color: '#4e4337',
        fontSize: 13,
        fontWeight: '700',
    },
    intervalChipTextActive: {
        color: '#fff6eb',
    },
});
