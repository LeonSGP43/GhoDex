import * as React from 'react';
import {
    ActivityIndicator,
    Alert,
    Modal,
    Pressable,
    ScrollView,
    StyleSheet,
    Text,
    TextInput,
    View,
} from 'react-native';
import { useRouter } from 'expo-router';
import { useFocusEffect } from '@react-navigation/native';
import { CameraView } from 'expo-camera';
import { pairingBegin, pairingExchange } from '@/ghodex/gateway';
import { parseGatewayPairingQrPayload } from '@/ghodex/pairingQr';
import { loadStoredSession, saveStoredSession, type StoredSession } from '@/ghodex/storage';
import { INITIAL_GATEWAY_SESSION } from '@/ghodex/sessionState';
import { ActionButton, InfoPill, SectionValue, SurfaceCard } from '@/ghodex/ui';
import { useCheckScannerPermissions } from '@/hooks/useCheckCameraPermissions';

type BusyAction = 'begin' | 'exchange' | 'scan' | null;

export default function GhoDexPairingScreen() {
    const router = useRouter();
    const checkScannerPermissions = useCheckScannerPermissions();
    const [loaded, setLoaded] = React.useState(false);
    const [busyAction, setBusyAction] = React.useState<BusyAction>(null);
    const [errorMessage, setErrorMessage] = React.useState<string | null>(null);
    const [embeddedScannerVisible, setEmbeddedScannerVisible] = React.useState(false);
    const [session, setSession] = React.useState<StoredSession>(INITIAL_GATEWAY_SESSION);
    const embeddedScannerLockedRef = React.useRef(false);

    useFocusEffect(React.useCallback(() => {
        let active = true;
        void (async () => {
            const stored = await loadStoredSession();
            if (!active) {
                return;
            }
            setSession(stored);
            setLoaded(true);
        })();

        return () => {
            active = false;
        };
    }, []));

    React.useEffect(() => {
        if (!loaded) {
            return;
        }
        void saveStoredSession(session);
    }, [loaded, session]);

    const runAction = React.useCallback(async (action: BusyAction, task: () => Promise<void>) => {
        setBusyAction(action);
        setErrorMessage(null);
        try {
            await task();
        } catch (error) {
            const message = error instanceof Error ? error.message : 'Unexpected gateway error';
            setErrorMessage(message);
        } finally {
            setBusyAction(null);
        }
    }, []);

    const setField = React.useCallback(function setField<K extends keyof StoredSession>(
        key: K,
        value: StoredSession[K],
    ) {
        setSession((current) => ({
            ...current,
            [key]: value,
        }));
    }, []);

    const handleBeginPairing = React.useCallback(() => {
        void runAction('begin', async () => {
            const result = await pairingBegin({
                host: session.host,
                port: session.port,
                client: 'ghodex-happy-client',
                requestedScopes: session.requestedScopes,
            });

            setSession((current) => ({
                ...current,
                pairingCode: result.pairingCode,
                scopes: result.scopes.length > 0 ? result.scopes : current.scopes,
            }));
        });
    }, [runAction, session.host, session.port, session.requestedScopes]);

    const handleExchangePairing = React.useCallback(() => {
        void runAction('exchange', async () => {
            const result = await pairingExchange({
                host: session.host,
                port: session.port,
                pairingCode: session.pairingCode,
            });

            const nextSession = {
                ...session,
                authToken: result.authToken,
                tokenId: result.tokenId ?? '',
                scopes: result.scopes,
            };
            setSession(nextSession);
            await saveStoredSession(nextSession);
            router.replace('/');
        });
    }, [router, runAction, session]);

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

            const nextSession: StoredSession = {
                ...session,
                host: payload.host,
                port: payload.port,
                pairingCode: payload.pairingCode,
                authToken: exchange.authToken,
                tokenId: exchange.tokenId ?? '',
                scopes: exchange.scopes,
            };
            setSession(nextSession);
            await saveStoredSession(nextSession);
            router.replace('/');
        });
    }, [router, runAction, session]);

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

    if (!loaded) {
        return (
            <View style={styles.loadingScreen}>
                <ActivityIndicator size="large" color="#8a4b2a" />
                <Text style={styles.loadingText}>Loading pairing flow…</Text>
            </View>
        );
    }

    return (
        <>
            <ScrollView style={styles.screen} contentContainerStyle={styles.content}>
                <SurfaceCard
                    title="Pair Desktop Gateway"
                    subtitle="This screen owns the full QR and pairing-code flow. After exchange it returns to the workspace automatically."
                >
                    <View style={styles.pillRow}>
                        <InfoPill icon="radio-outline" label={`${session.host}:${session.port}`} />
                        <InfoPill icon="key-outline" label={session.authToken ? 'Token ready' : 'Waiting for exchange'} />
                    </View>
                </SurfaceCard>

                <SurfaceCard title="Scan QR" subtitle="Use the desktop pairing QR for the fastest path.">
                    <View style={styles.actions}>
                        <ActionButton busy={busyAction === 'scan'} label="Scan Pairing QR" onPress={handleScanPairingQr} />
                    </View>
                </SurfaceCard>

                <SurfaceCard title="Manual Pairing" subtitle="Or request a pairing code from the current gateway endpoint.">
                    <SectionValue label="Requested scopes" mono value={session.requestedScopes.join(', ')} />
                    <View style={styles.actions}>
                        <ActionButton busy={busyAction === 'begin'} kind="secondary" label="Begin Pairing" onPress={handleBeginPairing} />
                    </View>
                    <TextInput
                        autoCapitalize="characters"
                        autoCorrect={false}
                        onChangeText={(value) => setField('pairingCode', value.trim())}
                        placeholder="PAIR-123"
                        placeholderTextColor="#8f867a"
                        style={styles.input}
                        value={session.pairingCode}
                    />
                    <TextInput
                        autoCapitalize="none"
                        autoCorrect={false}
                        multiline
                        onChangeText={(value) => setField('authToken', value.trim())}
                        placeholder="Scoped auth token"
                        placeholderTextColor="#8f867a"
                        style={[styles.input, styles.tokenInput]}
                        value={session.authToken}
                    />
                    <View style={styles.actions}>
                        <ActionButton busy={busyAction === 'exchange'} label="Exchange Pairing" onPress={handleExchangePairing} />
                        <ActionButton kind="secondary" label="Back To Workspace" onPress={() => router.replace('/')} />
                    </View>
                    <SectionValue label="Token id" mono value={session.tokenId || 'not issued yet'} />
                    <SectionValue label="Granted scopes" mono value={session.scopes.length > 0 ? session.scopes.join(', ') : 'none'} />
                    {errorMessage ? (
                        <View style={styles.errorBox}>
                            <Text style={styles.errorTitle}>Gateway error</Text>
                            <Text style={styles.errorText}>{errorMessage}</Text>
                        </View>
                    ) : null}
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
                        <Pressable onPress={dismissEmbeddedScanner} style={({ pressed }) => [styles.scannerCloseButton, pressed ? styles.buttonPressed : null]}>
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
        </>
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
    actions: {
        flexDirection: 'row',
        gap: 12,
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
    tokenInput: {
        minHeight: 92,
        textAlignVertical: 'top',
    },
    errorBox: {
        backgroundColor: '#fff0ec',
        borderColor: '#f2b4a5',
        borderRadius: 14,
        borderWidth: 1,
        padding: 12,
        gap: 4,
    },
    errorTitle: {
        color: '#8d2f1d',
        fontSize: 13,
        fontWeight: '700',
    },
    errorText: {
        color: '#6f3126',
        fontSize: 14,
        lineHeight: 20,
    },
    scannerScreen: {
        flex: 1,
        backgroundColor: '#15110d',
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
        color: '#fff8ef',
        fontSize: 24,
        fontWeight: '800',
    },
    scannerSubtitle: {
        color: '#d4c5b4',
        fontSize: 14,
        lineHeight: 20,
    },
    scannerCloseButton: {
        backgroundColor: '#2f2721',
        borderRadius: 12,
        paddingHorizontal: 14,
        paddingVertical: 10,
    },
    scannerCloseText: {
        color: '#fff8ef',
        fontSize: 14,
        fontWeight: '700',
    },
    scannerPreviewShell: {
        flex: 1,
        minHeight: 360,
        borderRadius: 28,
        overflow: 'hidden',
        backgroundColor: '#050505',
        borderWidth: 1,
        borderColor: '#4c4033',
    },
    scannerPreview: {
        flex: 1,
    },
    scannerGuide: {
        ...StyleSheet.absoluteFillObject,
        alignItems: 'center',
        justifyContent: 'center',
        backgroundColor: 'rgba(8, 6, 4, 0.28)',
    },
    scannerGuideFrame: {
        width: '68%',
        aspectRatio: 1,
        borderRadius: 28,
        borderWidth: 3,
        borderColor: '#f0c28f',
        backgroundColor: 'transparent',
    },
    buttonPressed: {
        opacity: 0.88,
    },
});
