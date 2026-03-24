import * as React from 'react';
import { ActivityIndicator, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { useRouter } from 'expo-router';
import { useFocusEffect } from '@react-navigation/native';
import { clearStoredSession, loadStoredSession, saveStoredSession } from '@/ghodex/storage';
import { INITIAL_GATEWAY_SESSION, sanitizePort } from '@/ghodex/sessionState';
import { ActionButton, InfoPill, SectionValue, SurfaceCard } from '@/ghodex/ui';

export default function GhoDexGatewayScreen() {
    const router = useRouter();
    const [loaded, setLoaded] = React.useState(false);
    const [host, setHost] = React.useState(INITIAL_GATEWAY_SESSION.host);
    const [portText, setPortText] = React.useState(String(INITIAL_GATEWAY_SESSION.port));

    useFocusEffect(React.useCallback(() => {
        let active = true;
        void (async () => {
            const stored = await loadStoredSession();
            if (!active) {
                return;
            }
            setHost(stored.host);
            setPortText(String(stored.port));
            setLoaded(true);
        })();

        return () => {
            active = false;
        };
    }, []));

    const handleApply = React.useCallback(async () => {
        const current = await loadStoredSession();
        await saveStoredSession({
            ...current,
            host: host.trim() || INITIAL_GATEWAY_SESSION.host,
            port: sanitizePort(portText),
        });
        router.replace('/');
    }, [host, portText, router]);

    const handleClear = React.useCallback(async () => {
        await clearStoredSession();
        router.replace('/');
    }, [router]);

    if (!loaded) {
        return (
            <View style={styles.loadingScreen}>
                <ActivityIndicator size="large" color="#8a4b2a" />
                <Text style={styles.loadingText}>Loading gateway settings…</Text>
            </View>
        );
    }

    return (
        <ScrollView style={styles.screen} contentContainerStyle={styles.content}>
            <SurfaceCard
                title="Gateway Settings"
                subtitle="This screen owns the connection endpoint. The workspace screen only consumes the saved endpoint."
            >
                <View style={styles.pillRow}>
                    <InfoPill icon="radio-outline" label={`${host || INITIAL_GATEWAY_SESSION.host}:${sanitizePort(portText)}`} />
                </View>
            </SurfaceCard>

            <SurfaceCard title="Endpoint" subtitle="Use 127.0.0.1 with adb reverse, or your desktop LAN IP when the phone connects directly.">
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
                <SectionValue label="Resolved port" mono value={String(sanitizePort(portText))} />
                <View style={styles.actions}>
                    <ActionButton label="Apply And Return" onPress={handleApply} />
                    <ActionButton kind="secondary" label="Open Pairing" onPress={() => router.push('/pairing')} />
                </View>
            </SurfaceCard>

            <SurfaceCard title="Session State" subtitle="Use this only when you want to fully reset the mobile side.">
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
});
