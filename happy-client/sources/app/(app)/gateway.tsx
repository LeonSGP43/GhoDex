import * as React from 'react';
import {
    ActivityIndicator,
    Alert,
    Modal,
    Pressable,
    ScrollView,
    Text,
    TextInput,
    View,
} from 'react-native';
import { useRouter } from 'expo-router';
import { useFocusEffect } from '@react-navigation/native';
import { CameraView } from 'expo-camera';
import { StyleSheet, useUnistyles } from 'react-native-unistyles';
import { pairingBegin, pairingExchange } from '@/ghodex/gateway';
import { parseGatewayPairingQrPayload } from '@/ghodex/pairingQr';
import { INITIAL_GATEWAY_SESSION, POLL_INTERVAL_OPTIONS, sanitizePollInterval, sanitizePort } from '@/ghodex/sessionState';
import { clearStoredSession, loadStoredSession, saveStoredSession, type StoredSession } from '@/ghodex/storage';
import { ActionButton, InfoPill, SectionValue, SurfaceCard } from '@/ghodex/ui';
import { useCheckScannerPermissions } from '@/hooks/useCheckCameraPermissions';
import { useConnectAccount } from '@/hooks/useConnectAccount';
import { useAllMachines } from '@/sync/storage';
import { isMachineOnline } from '@/utils/machineUtils';

type BusyAction = 'begin' | 'exchange' | 'scan' | 'save' | 'clear' | null;

export default function GhoDexGatewayScreen() {
    const { theme } = useUnistyles();
    const router = useRouter();
    const checkScannerPermissions = useCheckScannerPermissions();
    const { connectAccount, isLoading: accountLinking, scannerModal: accountScannerModal } = useConnectAccount();
    const allMachines = useAllMachines();
    const [loaded, setLoaded] = React.useState(false);
    const [busyAction, setBusyAction] = React.useState<BusyAction>(null);
    const [errorMessage, setErrorMessage] = React.useState<string | null>(null);
    const [embeddedScannerVisible, setEmbeddedScannerVisible] = React.useState(false);
    const [session, setSession] = React.useState<StoredSession>(INITIAL_GATEWAY_SESSION);
    const [host, setHost] = React.useState(INITIAL_GATEWAY_SESSION.host);
    const [portText, setPortText] = React.useState(String(INITIAL_GATEWAY_SESSION.port));
    const [liveUpdatesEnabled, setLiveUpdatesEnabled] = React.useState(INITIAL_GATEWAY_SESSION.liveUpdatesEnabled);
    const [pollIntervalMs, setPollIntervalMs] = React.useState(INITIAL_GATEWAY_SESSION.pollIntervalMs);
    const embeddedScannerLockedRef = React.useRef(false);

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

    const resolvedHost = host.trim() || INITIAL_GATEWAY_SESSION.host;
    const resolvedPort = sanitizePort(portText);
    const sanitizedPollIntervalMs = sanitizePollInterval(pollIntervalMs);
    const paired = !!session.authToken.trim();
    const sortedMachines = React.useMemo(() => {
        return [...allMachines].sort((left, right) => {
            const leftOnline = isMachineOnline(left);
            const rightOnline = isMachineOnline(right);
            if (leftOnline !== rightOnline) {
                return leftOnline ? -1 : 1;
            }
            return right.activeAt - left.activeAt;
        });
    }, [allMachines]);

    const buildSession = React.useCallback((base: StoredSession, delta?: Partial<StoredSession>): StoredSession => ({
        ...base,
        host: resolvedHost,
        port: resolvedPort,
        liveUpdatesEnabled,
        pollIntervalMs: sanitizedPollIntervalMs,
        ...delta,
    }), [liveUpdatesEnabled, resolvedHost, resolvedPort, sanitizedPollIntervalMs]);

    const runAction = React.useCallback(async (action: BusyAction, task: () => Promise<void>) => {
        setBusyAction(action);
        setErrorMessage(null);
        try {
            await task();
        } catch (error) {
            const message = error instanceof Error ? error.message : 'Unexpected device error';
            setErrorMessage(message);
        } finally {
            setBusyAction(null);
        }
    }, []);

    const dismissEmbeddedScanner = React.useCallback(() => {
        embeddedScannerLockedRef.current = false;
        setEmbeddedScannerVisible(false);
    }, []);

    const openEmbeddedScanner = React.useCallback(async () => {
        if (!(await checkScannerPermissions({ requireCameraOnAndroid: true }))) {
            const message = 'Camera permission is required to scan the pairing QR.';
            setErrorMessage(message);
            Alert.alert('Camera Permission Required', message);
            return false;
        }

        embeddedScannerLockedRef.current = false;
        setEmbeddedScannerVisible(true);
        return true;
    }, [checkScannerPermissions]);

    const handleSaveConnectionSettings = React.useCallback(() => {
        void runAction('save', async () => {
            const current = await loadStoredSession();
            const nextSession = buildSession(current);
            await saveStoredSession(nextSession);
            setSession(nextSession);
        });
    }, [buildSession, runAction]);

    const handleBeginPairing = React.useCallback(() => {
        void runAction('begin', async () => {
            const result = await pairingBegin({
                host: resolvedHost,
                port: resolvedPort,
                client: 'ghodex-happy-client',
                requestedScopes: session.requestedScopes,
            });

            const nextSession = buildSession(session, {
                pairingCode: result.pairingCode,
                scopes: result.scopes.length > 0 ? result.scopes : session.scopes,
            });
            await saveStoredSession(nextSession);
            setSession(nextSession);
        });
    }, [buildSession, resolvedHost, resolvedPort, runAction, session]);

    const handleExchangePairing = React.useCallback(() => {
        void runAction('exchange', async () => {
            const result = await pairingExchange({
                host: resolvedHost,
                port: resolvedPort,
                pairingCode: session.pairingCode,
            });

            const nextSession = buildSession(session, {
                authToken: result.authToken,
                tokenId: result.tokenId ?? '',
                scopes: result.scopes,
            });
            await saveStoredSession(nextSession);
            setSession(nextSession);
            router.replace('/');
        });
    }, [buildSession, resolvedHost, resolvedPort, router, runAction, session]);

    const handleGatewayPairingQr = React.useCallback((rawPayload: string) => {
        let payload: ReturnType<typeof parseGatewayPairingQrPayload>;
        try {
            payload = parseGatewayPairingQrPayload(rawPayload);
        } catch (error) {
            const message = error instanceof Error ? error.message : 'Unable to parse pairing QR';
            setErrorMessage(message);
            Alert.alert('Pairing QR Error', message);
            return;
        }

        void runAction('scan', async () => {
            const exchange = await pairingExchange({
                host: payload.host,
                port: payload.port,
                pairingCode: payload.pairingCode,
            });

            const nextSession = buildSession(session, {
                host: payload.host,
                port: payload.port,
                pairingCode: payload.pairingCode,
                authToken: exchange.authToken,
                tokenId: exchange.tokenId ?? '',
                scopes: exchange.scopes,
            });
            setHost(payload.host);
            setPortText(String(payload.port));
            await saveStoredSession(nextSession);
            setSession(nextSession);
            router.replace('/');
        });
    }, [buildSession, router, runAction, session]);

    const handleScanPairingQr = React.useCallback(async () => {
        setErrorMessage(null);

        if (!CameraView.isModernBarcodeScannerAvailable) {
            await openEmbeddedScanner();
            return;
        }

        if (!(await checkScannerPermissions())) {
            const message = 'Camera permission is required to scan the pairing QR.';
            setErrorMessage(message);
            Alert.alert('Camera Permission Required', message);
            return;
        }

        try {
            await CameraView.launchScanner({
                barcodeTypes: ['qr'],
            });
        } catch {
            await openEmbeddedScanner();
        }
    }, [checkScannerPermissions, openEmbeddedScanner]);

    const handleEmbeddedBarcodeScanned = React.useCallback(({ data }: { data: string }) => {
        if (embeddedScannerLockedRef.current) {
            return;
        }

        const payload = typeof data === 'string' ? data.trim() : String(data ?? '').trim();
        if (!payload) {
            return;
        }

        embeddedScannerLockedRef.current = true;
        setEmbeddedScannerVisible(false);
        handleGatewayPairingQr(payload);
    }, [handleGatewayPairingQr]);

    const handleEmbeddedScannerMountError = React.useCallback(({ message }: { message: string }) => {
        dismissEmbeddedScanner();
        setErrorMessage(message);
        Alert.alert('QR Scanner Error', message);
    }, [dismissEmbeddedScanner]);

    const handleClear = React.useCallback(() => {
        void runAction('clear', async () => {
            await clearStoredSession();
            setSession(INITIAL_GATEWAY_SESSION);
            setHost(INITIAL_GATEWAY_SESSION.host);
            setPortText(String(INITIAL_GATEWAY_SESSION.port));
            setLiveUpdatesEnabled(INITIAL_GATEWAY_SESSION.liveUpdatesEnabled);
            setPollIntervalMs(INITIAL_GATEWAY_SESSION.pollIntervalMs);
        });
    }, [runAction]);

    React.useEffect(() => {
        if (!CameraView.isModernBarcodeScannerAvailable) {
            return;
        }

        const subscription = CameraView.onModernBarcodeScanned(async (event) => {
            const payload = typeof event.data === 'string' ? event.data : String(event.data ?? '');
            await CameraView.dismissScanner();
            handleGatewayPairingQr(payload);
        });

        return () => {
            subscription.remove();
        };
    }, [handleGatewayPairingQr]);

    if (!loaded) {
        return (
            <View style={styles.loadingScreen}>
                <ActivityIndicator color={theme.colors.button.primary.background} size="large" />
                <Text style={styles.loadingText}>Loading device settings…</Text>
            </View>
        );
    }

    return (
        <>
            <ScrollView style={styles.screen} contentContainerStyle={styles.content}>
                <SurfaceCard
                    title="Device"
                    subtitle="Scan a desktop QR code to pair or replace the device linked to this phone."
                >
                    <View style={styles.pillRow}>
                        <InfoPill icon="radio-outline" label={`${resolvedHost}:${resolvedPort}`} />
                        <InfoPill icon="key-outline" label={paired ? 'Paired' : 'Awaiting pairing'} />
                        <InfoPill icon="sync-outline" label={liveUpdatesEnabled ? 'Realtime stream' : `Polling ${sanitizedPollIntervalMs}ms`} />
                    </View>
                    <View style={styles.actions}>
                        <ActionButton
                            busy={busyAction === 'scan'}
                            label={paired ? 'Scan To Replace Device' : 'Scan Pairing QR'}
                            onPress={() => {
                                void handleScanPairingQr();
                            }}
                        />
                        <ActionButton kind="secondary" label="Back To Workspace" onPress={() => router.replace('/')} />
                    </View>
                </SurfaceCard>

                {errorMessage ? (
                    <View style={styles.errorBox}>
                        <Text style={styles.errorTitle}>Device error</Text>
                        <Text style={styles.errorText}>{errorMessage}</Text>
                    </View>
                ) : null}

                <SurfaceCard
                    title="Saved Session"
                    subtitle="This phone keeps the current desktop session until you clear or replace it."
                >
                    <SectionValue label="Token" mono value={paired ? 'issued' : 'not issued'} />
                    <SectionValue label="Token id" mono value={session.tokenId || 'not issued yet'} />
                    <SectionValue label="Scopes" mono value={session.scopes.length > 0 ? session.scopes.join(', ') : 'none'} />
                </SurfaceCard>

                <SurfaceCard
                    title="Linked Phones"
                    subtitle="Authorize another phone for this account here so every device flow stays under Device."
                >
                    <View style={styles.actions}>
                        <ActionButton
                            busy={accountLinking}
                            kind="secondary"
                            label={accountLinking ? 'Scanning Account QR' : 'Link Another Phone'}
                            onPress={connectAccount}
                        />
                    </View>
                </SurfaceCard>

                {sortedMachines.length > 0 ? (
                    <SurfaceCard
                        title="Desktop Machines"
                        subtitle="Account-linked desktops live under Device so connection state and machine access stay in one place."
                    >
                        <View style={styles.machineList}>
                            {sortedMachines.map((machine) => {
                                const online = isMachineOnline(machine);
                                const host = machine.metadata?.host || 'Unknown host';
                                const name = machine.metadata?.displayName || host;
                                const platform = machine.metadata?.platform || '';
                                const metaParts = [];

                                if (name !== host) {
                                    metaParts.push(host);
                                }
                                if (platform) {
                                    metaParts.push(platform);
                                }
                                metaParts.push(online ? 'Online' : 'Offline');

                                return (
                                    <Pressable
                                        key={machine.id}
                                        onPress={() => router.push(`/machine/${machine.id}`)}
                                        style={({ pressed }) => [
                                            styles.machineRow,
                                            pressed ? styles.machineRowPressed : null,
                                        ]}
                                    >
                                        <View style={styles.machineInfo}>
                                            <Text numberOfLines={1} style={styles.machineTitle}>{name}</Text>
                                            <Text numberOfLines={2} style={styles.machineMeta}>{metaParts.join(' • ')}</Text>
                                        </View>
                                        <Text style={[styles.machineStatus, online ? styles.machineStatusOnline : styles.machineStatusOffline]}>
                                            {online ? 'Online' : 'Offline'}
                                        </Text>
                                    </Pressable>
                                );
                            })}
                        </View>
                    </SurfaceCard>
                ) : null}

                <SurfaceCard
                    title="Gateway Endpoint"
                    subtitle="Use this only when QR pairing needs a manual network fallback."
                >
                    <TextInput
                        autoCapitalize="none"
                        autoCorrect={false}
                        onChangeText={setHost}
                        placeholder="127.0.0.1"
                        placeholderTextColor={theme.colors.input.placeholder}
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
                        placeholderTextColor={theme.colors.input.placeholder}
                        style={styles.input}
                        value={portText}
                    />
                    <SectionValue label="Resolved port" mono value={String(resolvedPort)} />
                    <View style={styles.actions}>
                        <ActionButton busy={busyAction === 'save'} label="Save Connection" onPress={handleSaveConnectionSettings} />
                    </View>
                </SurfaceCard>

                <SurfaceCard
                    title="Sync Mode"
                    subtitle="Choose how this paired device refreshes desktop state."
                >
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
                        value={liveUpdatesEnabled ? 'Subscription stream for the active terminal' : 'Timer-based polling only'}
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

                <SurfaceCard
                    title="Manual Pairing"
                    subtitle="Fallback only for cases where QR scanning is unavailable."
                >
                    <SectionValue label="Requested scopes" mono value={session.requestedScopes.join(', ')} />
                    <View style={styles.actions}>
                        <ActionButton busy={busyAction === 'begin'} kind="secondary" label="Begin Pairing" onPress={handleBeginPairing} />
                    </View>
                    <TextInput
                        autoCapitalize="characters"
                        autoCorrect={false}
                        onChangeText={(value) => setSession((current) => ({ ...current, pairingCode: value.trim() }))}
                        placeholder="PAIR-123"
                        placeholderTextColor={theme.colors.input.placeholder}
                        style={styles.input}
                        value={session.pairingCode}
                    />
                    <View style={styles.actions}>
                        <ActionButton busy={busyAction === 'exchange'} label="Exchange Pairing" onPress={handleExchangePairing} />
                    </View>
                </SurfaceCard>

                <SurfaceCard
                    title="Reset Device"
                    subtitle="Remove the saved desktop session from this phone."
                >
                    <View style={styles.actions}>
                        <ActionButton busy={busyAction === 'clear'} kind="secondary" label="Clear Saved Session" onPress={handleClear} />
                    </View>
                </SurfaceCard>
            </ScrollView>

            <Modal
                animationType="slide"
                onRequestClose={dismissEmbeddedScanner}
                presentationStyle="fullScreen"
                visible={embeddedScannerVisible}
            >
                <View style={styles.scannerScreen}>
                    <View style={styles.scannerHeader}>
                        <View style={styles.scannerHeaderCopy}>
                            <Text style={styles.scannerTitle}>Scan Pairing QR</Text>
                            <Text style={styles.scannerSubtitle}>Point the rear camera at the desktop pairing code.</Text>
                        </View>
                        <Pressable
                            onPress={dismissEmbeddedScanner}
                            style={({ pressed }) => [styles.scannerCloseButton, pressed ? styles.optionChipPressed : null]}
                        >
                            <Text style={styles.scannerCloseText}>Close</Text>
                        </Pressable>
                    </View>

                    <View style={styles.scannerPreviewShell}>
                        <CameraView
                            barcodeScannerSettings={{ barcodeTypes: ['qr'] }}
                            facing="back"
                            onBarcodeScanned={handleEmbeddedBarcodeScanned}
                            onMountError={handleEmbeddedScannerMountError}
                            style={styles.scannerPreview}
                        />
                        <View pointerEvents="none" style={styles.scannerGuide}>
                            <View style={styles.scannerGuideFrame} />
                        </View>
                    </View>
                </View>
            </Modal>
            {accountScannerModal}
        </>
    );
}

const styles = StyleSheet.create((theme) => ({
    screen: {
        flex: 1,
        backgroundColor: theme.colors.groupped.background,
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
        backgroundColor: theme.colors.groupped.background,
    },
    loadingText: {
        color: theme.colors.text,
        fontSize: 16,
    },
    pillRow: {
        flexDirection: 'row',
        flexWrap: 'wrap',
        gap: 8,
    },
    input: {
        backgroundColor: theme.colors.input.background,
        borderWidth: 1,
        borderColor: theme.colors.divider,
        borderRadius: 14,
        paddingHorizontal: 14,
        paddingVertical: 12,
        color: theme.colors.input.text,
        fontSize: 16,
    },
    actions: {
        flexDirection: 'row',
        gap: 12,
    },
    machineList: {
        gap: 10,
    },
    machineRow: {
        flexDirection: 'row',
        alignItems: 'center',
        justifyContent: 'space-between',
        gap: 12,
        borderRadius: 14,
        borderWidth: 1,
        borderColor: theme.colors.divider,
        backgroundColor: theme.colors.surfaceHigh,
        paddingHorizontal: 14,
        paddingVertical: 12,
    },
    machineRowPressed: {
        opacity: 0.84,
    },
    machineInfo: {
        flex: 1,
        gap: 4,
    },
    machineTitle: {
        color: theme.colors.text,
        fontSize: 15,
        fontWeight: '700',
    },
    machineMeta: {
        color: theme.colors.textSecondary,
        fontSize: 13,
        lineHeight: 18,
    },
    machineStatus: {
        fontSize: 12,
        fontWeight: '800',
        textTransform: 'uppercase',
        letterSpacing: 0.6,
    },
    machineStatusOnline: {
        color: theme.colors.status.connected,
    },
    machineStatusOffline: {
        color: theme.colors.textSecondary,
    },
    optionLabel: {
        color: theme.colors.groupped.sectionTitle,
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
        backgroundColor: theme.colors.surfaceHigh,
        borderWidth: 1,
        borderColor: theme.colors.divider,
    },
    optionChipActive: {
        backgroundColor: theme.colors.button.primary.background,
        borderColor: theme.colors.button.primary.background,
    },
    optionChipPressed: {
        opacity: 0.84,
    },
    optionChipText: {
        color: theme.colors.text,
        fontSize: 14,
        fontWeight: '700',
    },
    optionChipTextActive: {
        color: theme.colors.button.primary.tint,
    },
    intervalChip: {
        borderRadius: 999,
        paddingHorizontal: 12,
        paddingVertical: 9,
        backgroundColor: theme.colors.surface,
        borderWidth: 1,
        borderColor: theme.colors.divider,
    },
    intervalChipActive: {
        backgroundColor: theme.colors.button.primary.background,
        borderColor: theme.colors.button.primary.background,
    },
    intervalChipText: {
        color: theme.colors.text,
        fontSize: 13,
        fontWeight: '700',
    },
    intervalChipTextActive: {
        color: theme.colors.button.primary.tint,
    },
    errorBox: {
        backgroundColor: theme.colors.box.error.background,
        borderColor: theme.colors.box.error.border,
        borderRadius: 14,
        borderWidth: 1,
        padding: 12,
        gap: 4,
        marginHorizontal: 16,
    },
    errorTitle: {
        color: theme.colors.box.error.text,
        fontSize: 13,
        fontWeight: '700',
    },
    errorText: {
        color: theme.colors.text,
        fontSize: 14,
        lineHeight: 20,
    },
    scannerScreen: {
        flex: 1,
        backgroundColor: theme.colors.groupped.background,
        paddingHorizontal: 18,
        paddingTop: 20,
        paddingBottom: 28,
        gap: 18,
    },
    scannerHeader: {
        flexDirection: 'row',
        alignItems: 'flex-start',
        justifyContent: 'space-between',
        gap: 12,
    },
    scannerHeaderCopy: {
        flex: 1,
        gap: 6,
    },
    scannerTitle: {
        color: theme.colors.text,
        fontSize: 24,
        fontWeight: '800',
    },
    scannerSubtitle: {
        color: theme.colors.textSecondary,
        fontSize: 14,
        lineHeight: 20,
    },
    scannerCloseButton: {
        backgroundColor: theme.colors.surfaceHigh,
        borderRadius: 12,
        borderWidth: 1,
        borderColor: theme.colors.divider,
        paddingHorizontal: 14,
        paddingVertical: 10,
    },
    scannerCloseText: {
        color: theme.colors.text,
        fontSize: 14,
        fontWeight: '700',
    },
    scannerPreviewShell: {
        flex: 1,
        minHeight: 360,
        borderRadius: 28,
        overflow: 'hidden',
        backgroundColor: theme.colors.terminal.background,
        borderWidth: 1,
        borderColor: theme.colors.divider,
    },
    scannerPreview: {
        flex: 1,
    },
    scannerGuide: {
        ...StyleSheet.absoluteFillObject,
        alignItems: 'center',
        justifyContent: 'center',
        backgroundColor: theme.dark ? 'rgba(0, 0, 0, 0.28)' : 'rgba(255, 255, 255, 0.22)',
    },
    scannerGuideFrame: {
        width: '68%',
        aspectRatio: 1,
        borderRadius: 28,
        borderWidth: 3,
        borderColor: theme.colors.button.primary.background,
        backgroundColor: 'transparent',
    },
}));
