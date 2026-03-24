import * as React from 'react';
import {
    ActivityIndicator,
    Alert,
    Modal,
    Platform,
    Pressable,
    RefreshControl,
    ScrollView,
    StyleSheet,
    Text,
    TextInput,
    View,
} from 'react-native';
import { CameraView } from 'expo-camera';
import {
    DEFAULT_REQUESTED_SCOPES,
    fetchSnapshot,
    pairingBegin,
    pairingExchange,
    readTerminal,
    sendTerminalText,
    runTerminalCommand,
} from '@/ghodex/gateway';
import { parseGatewayPairingQrPayload } from '@/ghodex/pairingQr';
import { clearStoredSession, loadStoredSession, saveStoredSession, type StoredSession } from '@/ghodex/storage';
import type { SnapshotResult, TerminalChangedRow, TerminalReadResult, TerminalRow } from '@/ghodex/types';
import { useCheckScannerPermissions } from '@/hooks/useCheckCameraPermissions';

const INITIAL_SESSION: StoredSession = {
    host: '127.0.0.1',
    port: 19527,
    pairingCode: '',
    authToken: '',
    tokenId: '',
    scopes: [],
    requestedScopes: [...DEFAULT_REQUESTED_SCOPES],
};

type BusyAction =
    | 'begin'
    | 'exchange'
    | 'snapshot'
    | 'clear'
    | 'scan'
    | 'terminal-read'
    | 'terminal-command'
    | 'terminal-send-text'
    | null;

const DELTA_POLL_INTERVAL_MS = 350;
const WRITE_SETTLE_ATTEMPTS = 6;
const WRITE_SETTLE_INTERVAL_MS = 250;
const SNAPSHOT_RETRY_INTERVAL_MS = 3000;

function sleep(ms: number): Promise<void> {
    return new Promise((resolve) => {
        setTimeout(resolve, ms);
    });
}

function applyTerminalDelta(content: string, changedRows: TerminalChangedRow[]): string | null {
    if (changedRows.length === 0) {
        return content;
    }

    const nextLines = content.split('\n');
    for (const row of [...changedRows].sort((left, right) => left.index - right.index)) {
        while (nextLines.length < row.index) {
            nextLines.push('');
        }

        switch (row.kind) {
        case 'insert':
            nextLines.splice(row.index, 0, row.text ?? '');
            break;
        case 'update':
            while (nextLines.length <= row.index) {
                nextLines.push('');
            }
            nextLines[row.index] = row.text ?? '';
            break;
        case 'delete':
            if (row.index < nextLines.length) {
                nextLines.splice(row.index, 1);
            }
            break;
        default:
            return null;
        }
    }

    return nextLines.join('\n');
}

export default function GhoDexHomeScreen() {
    const checkScannerPermissions = useCheckScannerPermissions();
    const [loaded, setLoaded] = React.useState(false);
    const [busyAction, setBusyAction] = React.useState<BusyAction>(null);
    const [errorMessage, setErrorMessage] = React.useState<string | null>(null);
    const [embeddedScannerVisible, setEmbeddedScannerVisible] = React.useState(false);
    const [session, setSession] = React.useState<StoredSession>(INITIAL_SESSION);
    const [snapshot, setSnapshot] = React.useState<SnapshotResult | null>(null);
    const [selectedTerminalId, setSelectedTerminalId] = React.useState<string | null>(null);
    const [terminalView, setTerminalView] = React.useState<TerminalReadResult | null>(null);
    const [terminalContent, setTerminalContent] = React.useState('');
    const [terminalCommand, setTerminalCommand] = React.useState('');
    const embeddedScannerLockedRef = React.useRef(false);
    const terminalPollInFlightRef = React.useRef(false);

    React.useEffect(() => {
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
    }, []);

    React.useEffect(() => {
        if (!loaded) {
            return;
        }
        void saveStoredSession(session);
    }, [loaded, session]);

    const setField = React.useCallback(function setField<K extends keyof StoredSession>(
        key: K,
        value: StoredSession[K],
    ) {
        setSession((current) => ({
            ...current,
            [key]: value,
        }));
    }, []);

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

    const selectedTerminal = React.useMemo(
        () => snapshot?.terminals.find((terminal) => terminal.terminalId === selectedTerminalId) ?? null,
        [selectedTerminalId, snapshot],
    );

    const applyTerminalResult = React.useCallback((
        result: TerminalReadResult,
        options?: {
            mergeDelta?: boolean;
        },
    ) => {
        setTerminalView(result);
        setTerminalContent((current) => {
            if (options?.mergeDelta && result.mode === 'delta' && result.contentKind === 'delta') {
                if (!result.hasChanges) {
                    return current;
                }

                const merged = applyTerminalDelta(current, result.changedRows);
                if (merged !== null) {
                    return merged;
                }
            }

            return result.content;
        });

        setSnapshot((current) => {
            if (!current) {
                return current;
            }
            return {
                ...current,
                lastSequence: Math.max(current.lastSequence, result.lastSequence),
                terminals: current.terminals.map((item) => (
                    item.terminalId === result.terminalId
                        ? { ...item, generation: result.generation }
                        : item
                )),
            };
        });
    }, []);

    const loadTerminalView = React.useCallback(async (
        terminal: TerminalRow,
        authToken: string,
        options?: {
            expectedGeneration?: number;
            mode?: 'snapshot' | 'delta';
            sinceFrameId?: string;
            readAfterWriteId?: string;
        },
    ) => {
        const result = await readTerminal({
            host: session.host,
            port: session.port,
            authToken,
            terminalId: terminal.terminalId,
            expectedGeneration: options?.expectedGeneration ?? terminal.generation,
            mode: options?.mode ?? 'snapshot',
            sinceFrameId: options?.sinceFrameId,
            maxChars: 24_000,
            maxLines: 300,
            readAfterWriteId: options?.readAfterWriteId,
        });
        const expectsDelta = options?.mode === 'delta';
        const sameTerminal = terminalView?.terminalId === result.terminalId;
        const canMergeDelta = expectsDelta
            && !!options?.sinceFrameId
            && sameTerminal
            && (
                result.parentFrameId === options.sinceFrameId
                || (!result.hasChanges && result.frameId === options.sinceFrameId)
            );
        const deltaNeedsSnapshotFallback = expectsDelta && (
            !canMergeDelta
            || (result.hasChanges && result.changedRows.length === 0)
        );

        if (deltaNeedsSnapshotFallback) {
            const snapshotResult = await readTerminal({
                host: session.host,
                port: session.port,
                authToken,
                terminalId: terminal.terminalId,
                expectedGeneration: options?.expectedGeneration ?? result.generation,
                mode: 'snapshot',
                maxChars: 24_000,
                maxLines: 300,
                readAfterWriteId: options?.readAfterWriteId,
            });
            applyTerminalResult(snapshotResult);
            return snapshotResult;
        }

        applyTerminalResult(result, { mergeDelta: expectsDelta });

        return result;
    }, [applyTerminalResult, session.host, session.port, terminalView?.terminalId]);

    const settleTerminalAfterWrite = React.useCallback(async (
        terminal: TerminalRow,
        authToken: string,
        generation: number,
        writeId?: string,
    ) => {
        let sinceFrameId = terminalView?.terminalId === terminal.terminalId ? terminalView.frameId ?? undefined : undefined;

        for (let attempt = 0; attempt < WRITE_SETTLE_ATTEMPTS; attempt += 1) {
            if (attempt > 0) {
                await sleep(WRITE_SETTLE_INTERVAL_MS);
            }

            const result = await loadTerminalView(terminal, authToken, {
                expectedGeneration: generation,
                mode: sinceFrameId ? 'delta' : 'snapshot',
                sinceFrameId,
                readAfterWriteId: writeId,
            });

            sinceFrameId = result.frameId ?? sinceFrameId;
            const writeSettled = writeId
                ? result.readAfterReady === true
                : result.hasChanges;
            if (writeSettled) {
                return result;
            }
        }

        return loadTerminalView(terminal, authToken, {
            expectedGeneration: generation,
            readAfterWriteId: writeId,
        });
    }, [loadTerminalView, terminalView?.frameId, terminalView?.terminalId]);

    const refreshSnapshot = React.useCallback(async (
        authToken: string,
        preferredTerminalId: string | null,
    ) => {
        const result = await fetchSnapshot({
            host: session.host,
            port: session.port,
            authToken,
        });
        setSnapshot(result);

        const nextTerminal = pickPreferredTerminal(result.terminals, preferredTerminalId);
        setSelectedTerminalId(nextTerminal?.terminalId ?? null);
        if (nextTerminal) {
            await loadTerminalView(nextTerminal, authToken);
        } else {
            setTerminalView(null);
            setTerminalContent('');
        }

        return result;
    }, [loadTerminalView, session.host, session.port]);

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

            setSession((current) => ({
                ...current,
                authToken: result.authToken,
                tokenId: result.tokenId ?? '',
                scopes: result.scopes,
            }));
        });
    }, [runAction, session.host, session.pairingCode, session.port]);

    const handleRefreshSnapshot = React.useCallback(() => {
        if (!session.authToken.trim()) {
            setErrorMessage('Auth token is empty. Exchange pairing first or paste a token.');
            return;
        }

        void runAction('snapshot', async () => {
            await refreshSnapshot(session.authToken, selectedTerminalId);
        });
    }, [refreshSnapshot, runAction, selectedTerminalId, session.authToken]);

    const handleClearSession = React.useCallback(() => {
        void runAction('clear', async () => {
            await clearStoredSession();
            setSession(INITIAL_SESSION);
            setSnapshot(null);
            setSelectedTerminalId(null);
            setTerminalView(null);
            setTerminalContent('');
            setTerminalCommand('');
        });
    }, [runAction]);

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
            setSession((current) => ({
                ...current,
                host: payload.host,
                port: payload.port,
                pairingCode: payload.pairingCode,
            }));

            const exchange = await pairingExchange({
                host: payload.host,
                port: payload.port,
                pairingCode: payload.pairingCode,
            });

            setSession((current) => ({
                ...current,
                host: payload.host,
                port: payload.port,
                pairingCode: payload.pairingCode,
                authToken: exchange.authToken,
                tokenId: exchange.tokenId ?? '',
                scopes: exchange.scopes,
            }));

            try {
                await refreshSnapshot(exchange.authToken, null);
            } catch (error) {
                const message = error instanceof Error ? error.message : 'Snapshot refresh failed';
                setErrorMessage(
                    `Pairing succeeded, but the first snapshot did not load. Close the desktop QR window and pull to refresh. Details: ${message}`,
                );
                setSnapshot(null);
                setSelectedTerminalId(null);
                setTerminalView(null);
                setTerminalContent('');
            }
        });
    }, [refreshSnapshot, runAction]);

    const handleSelectTerminal = React.useCallback((terminal: TerminalRow) => {
        if (!session.authToken.trim()) {
            setErrorMessage('Auth token is empty. Exchange pairing first or paste a token.');
            return;
        }

        setSelectedTerminalId(terminal.terminalId);
        setTerminalContent('');
        void runAction('terminal-read', async () => {
            await loadTerminalView(terminal, session.authToken);
        });
    }, [loadTerminalView, runAction, session.authToken]);

    const handleRefreshTerminal = React.useCallback(() => {
        if (!selectedTerminal) {
            setErrorMessage('Select a terminal from the snapshot list first.');
            return;
        }

        void runAction('terminal-read', async () => {
            await loadTerminalView(
                selectedTerminal,
                session.authToken,
                terminalView?.terminalId === selectedTerminal.terminalId
                    ? { expectedGeneration: terminalView.generation, mode: 'snapshot' }
                    : undefined,
            );
        });
    }, [loadTerminalView, runAction, selectedTerminal, session.authToken, terminalView]);

    const handleRunTerminalCommand = React.useCallback(() => {
        if (!selectedTerminal) {
            setErrorMessage('Select a terminal from the snapshot list first.');
            return;
        }

        const commandText = terminalCommand.trim();
        if (!commandText) {
            setErrorMessage('Command input is empty.');
            return;
        }

        void runAction('terminal-command', async () => {
            const expectedGeneration = terminalView?.terminalId === selectedTerminal.terminalId
                ? terminalView.generation
                : selectedTerminal.generation;
            const mutation = await runTerminalCommand({
                host: session.host,
                port: session.port,
                authToken: session.authToken,
                terminalId: selectedTerminal.terminalId,
                commandText,
                expectedGeneration,
            });
            setTerminalCommand('');
            await settleTerminalAfterWrite(
                selectedTerminal,
                session.authToken,
                mutation.generation,
                mutation.writeId ?? undefined,
            );
        });
    }, [runAction, selectedTerminal, session.authToken, session.host, session.port, settleTerminalAfterWrite, terminalCommand, terminalView]);

    const handleSendTerminalText = React.useCallback(() => {
        if (!selectedTerminal) {
            setErrorMessage('Select a terminal from the snapshot list first.');
            return;
        }

        if (!terminalCommand) {
            setErrorMessage('Input is empty.');
            return;
        }

        void runAction('terminal-send-text', async () => {
            const expectedGeneration = terminalView?.terminalId === selectedTerminal.terminalId
                ? terminalView.generation
                : selectedTerminal.generation;
            const mutation = await sendTerminalText({
                host: session.host,
                port: session.port,
                authToken: session.authToken,
                terminalId: selectedTerminal.terminalId,
                text: terminalCommand,
                expectedGeneration,
            });
            setTerminalCommand('');
            await settleTerminalAfterWrite(
                selectedTerminal,
                session.authToken,
                mutation.generation,
                mutation.writeId ?? undefined,
            );
        });
    }, [runAction, selectedTerminal, session.authToken, session.host, session.port, settleTerminalAfterWrite, terminalCommand, terminalView]);

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
        } catch (error) {
            const fallbackOpened = await openEmbeddedScanner();
            if (!fallbackOpened) {
                const message = error instanceof Error ? error.message : 'Unable to open the QR scanner.';
                setErrorMessage(message);
                Alert.alert('QR Scanner Unavailable', message);
            }
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

    const statusLabel = React.useMemo(() => {
        if (busyAction === 'begin') {
            return 'Requesting pairing code from desktop gateway...';
        }
        if (busyAction === 'exchange') {
            return 'Exchanging pairing code for scoped auth token...';
        }
        if (busyAction === 'scan') {
            return 'Applying scanned pairing payload and fetching a fresh snapshot...';
        }
        if (busyAction === 'snapshot') {
            return 'Fetching live terminal snapshot and refreshing the selected terminal view...';
        }
        if (busyAction === 'terminal-read') {
            return 'Reading the selected terminal surface from the desktop gateway...';
        }
        if (busyAction === 'terminal-command') {
            return 'Sending the command to the selected desktop terminal and waiting for the next read...';
        }
        if (busyAction === 'terminal-send-text') {
            return 'Sending raw input to the selected desktop terminal and waiting for the next read...';
        }
        if (!loaded) {
            return 'Loading saved gateway session...';
        }
        if (terminalView) {
            return `Viewing terminal ${terminalView.terminalId.slice(0, 8)} via ${terminalView.mode}/${terminalView.contentKind}. Sequence ${terminalView.lastSequence}.`;
        }
        if (snapshot) {
            return `Connected. Protocol ${snapshot.protocolVersion ?? 'unknown'} with ${snapshot.terminals.length} terminal(s).`;
        }
        if (session.authToken) {
            return 'Paired. You can refresh a snapshot now.';
        }
        if (session.pairingCode) {
            return 'Pairing code issued. Exchange it on this screen.';
        }
        return 'Ready to pair with a local GhoDex control gateway.';
    }, [busyAction, loaded, session.authToken, session.pairingCode, snapshot]);

    React.useEffect(() => {
        if (!CameraView.isModernBarcodeScannerAvailable) {
            return;
        }

        const subscription = CameraView.onModernBarcodeScanned(async (event) => {
            const payload = typeof event.data === 'string' ? event.data : String(event.data ?? '');
            if (Platform.OS === 'ios') {
                await CameraView.dismissScanner();
            }
            handleGatewayPairingQr(payload);
        });

        return () => {
            subscription.remove();
        };
    }, [handleGatewayPairingQr]);

    React.useEffect(() => {
        const authToken = session.authToken.trim();
        if (!loaded || !authToken || snapshot || busyAction) {
            return;
        }

        const timer = setTimeout(() => {
            void runAction('snapshot', async () => {
                await refreshSnapshot(authToken, selectedTerminalId);
            });
        }, SNAPSHOT_RETRY_INTERVAL_MS);

        return () => {
            clearTimeout(timer);
        };
    }, [busyAction, loaded, refreshSnapshot, runAction, selectedTerminalId, session.authToken, snapshot]);

    React.useEffect(() => {
        const authToken = session.authToken.trim();
        if (!loaded || !authToken || !selectedTerminal) {
            return;
        }

        let cancelled = false;
        let timer: ReturnType<typeof setTimeout> | null = null;

        const schedule = () => {
            if (cancelled) {
                return;
            }
            timer = setTimeout(tick, DELTA_POLL_INTERVAL_MS);
        };

        const tick = async () => {
            if (cancelled) {
                return;
            }
            if (busyAction || terminalPollInFlightRef.current) {
                schedule();
                return;
            }

            terminalPollInFlightRef.current = true;
            try {
                await loadTerminalView(selectedTerminal, authToken, {
                    expectedGeneration: terminalView?.terminalId === selectedTerminal.terminalId
                        ? terminalView.generation
                        : selectedTerminal.generation,
                    mode: terminalView?.terminalId === selectedTerminal.terminalId && terminalView.frameId
                        ? 'delta'
                        : 'snapshot',
                    sinceFrameId: terminalView?.terminalId === selectedTerminal.terminalId
                        ? terminalView.frameId ?? undefined
                        : undefined,
                });
            } catch (error) {
                console.warn('Failed to refresh terminal view', error);
            } finally {
                terminalPollInFlightRef.current = false;
                schedule();
            }
        };

        schedule();

        return () => {
            cancelled = true;
            if (timer) {
                clearTimeout(timer);
            }
        };
    }, [busyAction, loadTerminalView, loaded, selectedTerminal, session.authToken, terminalView]);

    if (!loaded) {
        return (
            <View style={styles.loadingScreen}>
                <ActivityIndicator size="large" color="#8a4b2a" />
                <Text style={styles.loadingText}>Loading GhoDex gateway shell…</Text>
            </View>
        );
    }

    return (
        <>
            <ScrollView
                style={styles.screen}
                contentContainerStyle={styles.content}
                refreshControl={
                    <RefreshControl
                        refreshing={busyAction === 'snapshot'}
                        onRefresh={handleRefreshSnapshot}
                        tintColor="#8a4b2a"
                    />
                }
            >
                <View style={styles.heroCard}>
                    <Text style={styles.eyebrow}>Sidecar Client</Text>
                    <Text style={styles.title}>Mobile pairing shell for the existing desktop gateway</Text>
                    <Text style={styles.subtitle}>
                        This fork keeps the current macOS auth boundary and only swaps in a thinner Expo mobile client.
                    </Text>
                    <View style={styles.statusRow}>
                        {busyAction ? <ActivityIndicator color="#8a4b2a" /> : <View style={styles.statusDot} />}
                        <Text style={styles.statusText}>{statusLabel}</Text>
                    </View>
                    <Text style={styles.notice}>
                        On a physical Android phone, <Text style={styles.noticeStrong}>127.0.0.1 only works if you set up `adb reverse`</Text> or point
                        the app at your desktop&apos;s reachable LAN IP.
                    </Text>
                </View>

                <View style={styles.card}>
                    <Text style={styles.sectionTitle}>Gateway</Text>
                    <TextInput
                        autoCapitalize="none"
                        autoCorrect={false}
                        onChangeText={(value) => setField('host', value)}
                        placeholder="127.0.0.1"
                        placeholderTextColor="#8f867a"
                        style={styles.input}
                        value={session.host}
                    />
                    <TextInput
                        autoCapitalize="none"
                        autoCorrect={false}
                        inputMode="numeric"
                        keyboardType="number-pad"
                        onChangeText={(value) => setField('port', sanitizePort(value))}
                        placeholder="19527"
                        placeholderTextColor="#8f867a"
                        style={styles.input}
                        value={session.port.toString()}
                    />
                    <View style={styles.actionRow}>
                        <ActionButton
                            busy={busyAction === 'begin'}
                            label="Begin Pairing"
                            onPress={handleBeginPairing}
                        />
                        <ActionButton
                            busy={busyAction === 'scan'}
                            kind="secondary"
                            label="Scan Pairing QR"
                            onPress={handleScanPairingQr}
                        />
                    </View>
                    <View style={styles.actionRow}>
                        <ActionButton
                            busy={busyAction === 'clear'}
                            kind="secondary"
                            label="Clear"
                            onPress={handleClearSession}
                        />
                    </View>
                </View>

                <View style={styles.card}>
                    <Text style={styles.sectionTitle}>Credentials</Text>
                    <LabeledValue label="Requested scopes" value={session.requestedScopes.join(', ')} mono />
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
                    <View style={styles.actionRow}>
                        <ActionButton
                            busy={busyAction === 'exchange'}
                            label="Exchange Pairing"
                            onPress={handleExchangePairing}
                        />
                        <ActionButton
                            busy={busyAction === 'snapshot'}
                            kind="secondary"
                            label="Refresh Snapshot"
                            onPress={handleRefreshSnapshot}
                        />
                    </View>
                    <LabeledValue label="Token id" value={session.tokenId || 'not issued yet'} mono />
                    <LabeledValue label="Granted scopes" value={session.scopes.length > 0 ? session.scopes.join(', ') : 'none'} mono />
                    {errorMessage ? (
                        <View style={styles.errorBox}>
                            <Text style={styles.errorTitle}>Gateway error</Text>
                            <Text style={styles.errorText}>{errorMessage}</Text>
                        </View>
                    ) : null}
                </View>

                <View style={styles.card}>
                    <Text style={styles.sectionTitle}>Snapshot</Text>
                    <LabeledValue label="Protocol" value={snapshot?.protocolVersion ?? 'unknown'} mono />
                    <LabeledValue label="Last sequence" value={snapshot ? String(snapshot.lastSequence) : '0'} mono />
                    {snapshot?.terminals.length ? (
                        snapshot.terminals.map((terminal) => (
                            <TerminalCard
                                key={terminal.terminalId}
                                onPress={() => handleSelectTerminal(terminal)}
                                selected={terminal.terminalId === selectedTerminalId}
                                terminal={terminal}
                            />
                        ))
                    ) : (
                        <Text style={styles.emptyState}>
                            No terminal rows yet. After pairing, refresh snapshot to list active desktop terminals.
                        </Text>
                    )}
                </View>

                <View style={styles.card}>
                    <Text style={styles.sectionTitle}>Terminal View</Text>
                    {selectedTerminal ? (
                        <>
                            <LabeledValue label="Terminal id" value={selectedTerminal.terminalId} mono />
                            <LabeledValue label="Title" value={selectedTerminal.title || 'untitled terminal'} />
                            <LabeledValue label="Working directory" value={selectedTerminal.workingDirectory || 'working directory unavailable'} mono />
                            <LabeledValue
                                label="Read consistency"
                                value={terminalView ? `${terminalView.consistency} / ${terminalView.returnedLines} lines` : 'not read yet'}
                            />
                            <View style={styles.actionRow}>
                                <ActionButton
                                    busy={busyAction === 'terminal-read'}
                                    kind="secondary"
                                    label="Refresh Terminal"
                                    onPress={handleRefreshTerminal}
                                />
                            </View>
                            <TextInput
                                autoCapitalize="none"
                                autoCorrect={false}
                                multiline
                                onChangeText={setTerminalCommand}
                                placeholder="pwd or raw text input"
                                placeholderTextColor="#8f867a"
                                style={[styles.input, styles.commandInput, styles.monoText]}
                                value={terminalCommand}
                            />
                            <View style={styles.actionRow}>
                                <ActionButton
                                    busy={busyAction === 'terminal-send-text'}
                                    kind="secondary"
                                    label="Send Text"
                                    onPress={handleSendTerminalText}
                                />
                                <ActionButton
                                    busy={busyAction === 'terminal-command'}
                                    label="Run Command"
                                    onPress={handleRunTerminalCommand}
                                />
                            </View>
                            <View style={styles.terminalViewport}>
                                <ScrollView nestedScrollEnabled style={styles.terminalViewportScroll}>
                                    <Text selectable style={styles.terminalContent}>
                                        {terminalContent || 'No terminal text captured yet. Tap Refresh Terminal to read the visible surface.'}
                                    </Text>
                                </ScrollView>
                            </View>
                            {terminalView?.truncated ? (
                                <Text style={styles.terminalHint}>
                                    The terminal read was truncated to fit the mobile view budget. Refresh again after scrolling on desktop if you need a different window.
                                </Text>
                            ) : null}
                        </>
                    ) : (
                        <Text style={styles.emptyState}>
                            Select a terminal row above to open its current visible content here.
                        </Text>
                    )}
                </View>
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

                    <Text style={styles.scannerHint}>
                        If the QR code is small, enlarge it on the desktop or move the phone closer until it locks.
                    </Text>
                </View>
            </Modal>
        </>
    );
}

function sanitizePort(raw: string): number {
    const digits = raw.replace(/[^0-9]/g, '');
    if (!digits) {
        return INITIAL_SESSION.port;
    }
    const next = Number.parseInt(digits, 10);
    if (!Number.isFinite(next) || next <= 0) {
        return INITIAL_SESSION.port;
    }
    return Math.min(next, 65535);
}

function ActionButton({
    busy,
    kind = 'primary',
    label,
    onPress,
}: {
    busy?: boolean;
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

function LabeledValue({ label, value, mono = false }: { label: string; value: string; mono?: boolean }) {
    return (
        <View style={styles.metaRow}>
            <Text style={styles.metaLabel}>{label}</Text>
            <Text style={[styles.metaValue, mono ? styles.monoText : null]}>{value}</Text>
        </View>
    );
}

function TerminalCard({
    terminal,
    selected,
    onPress,
}: {
    terminal: TerminalRow;
    selected: boolean;
    onPress: () => void;
}) {
    return (
        <Pressable
            onPress={onPress}
            style={({ pressed }) => [
                styles.terminalCard,
                selected ? styles.terminalCardSelected : null,
                pressed ? styles.buttonPressed : null,
            ]}
        >
            <View style={styles.terminalHeader}>
                <Text style={styles.terminalTitle}>{terminal.title || terminal.terminalId}</Text>
                <Text style={styles.terminalBadge}>{terminal.focused ? 'focused' : terminal.visible ? 'visible' : 'idle'}</Text>
            </View>
            <Text style={styles.terminalMeta}>{terminal.terminalId}</Text>
            <Text style={styles.terminalMeta}>{terminal.workingDirectory || 'working directory unavailable'}</Text>
            <Text style={styles.terminalMeta}>generation {terminal.generation}</Text>
        </Pressable>
    );
}

function pickPreferredTerminal(terminals: TerminalRow[], preferredTerminalId: string | null): TerminalRow | null {
    if (!terminals.length) {
        return null;
    }
    if (preferredTerminalId) {
        const matched = terminals.find((terminal) => terminal.terminalId === preferredTerminalId);
        if (matched) {
            return matched;
        }
    }
    return terminals.find((terminal) => terminal.focused) ?? terminals[0] ?? null;
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
    heroCard: {
        backgroundColor: '#1f1a16',
        borderRadius: 24,
        padding: 20,
        gap: 12,
    },
    eyebrow: {
        color: '#f0c28f',
        fontSize: 12,
        fontWeight: '700',
        letterSpacing: 1,
        textTransform: 'uppercase',
    },
    title: {
        color: '#fff8ef',
        fontSize: 28,
        fontWeight: '800',
        lineHeight: 34,
    },
    subtitle: {
        color: '#d8cbbb',
        fontSize: 15,
        lineHeight: 22,
    },
    statusRow: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: 10,
        marginTop: 4,
    },
    statusDot: {
        width: 10,
        height: 10,
        borderRadius: 999,
        backgroundColor: '#4fb286',
    },
    statusText: {
        flex: 1,
        color: '#fff8ef',
        fontSize: 14,
        lineHeight: 20,
    },
    notice: {
        color: '#f0dfcd',
        fontSize: 13,
        lineHeight: 20,
    },
    noticeStrong: {
        fontWeight: '700',
        color: '#fff8ef',
    },
    card: {
        backgroundColor: '#fbf7f0',
        borderRadius: 20,
        padding: 16,
        gap: 12,
        borderWidth: 1,
        borderColor: '#e8ddd0',
    },
    sectionTitle: {
        color: '#241d17',
        fontSize: 18,
        fontWeight: '700',
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
    actionRow: {
        flexDirection: 'row',
        gap: 12,
        flexWrap: 'wrap',
    },
    button: {
        flex: 1,
        minHeight: 48,
        borderRadius: 14,
        alignItems: 'center',
        justifyContent: 'center',
        paddingHorizontal: 12,
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
    emptyState: {
        color: '#6e655b',
        fontSize: 14,
        lineHeight: 20,
    },
    terminalCard: {
        backgroundColor: '#fffdf9',
        borderRadius: 16,
        borderWidth: 1,
        borderColor: '#eadfce',
        padding: 14,
        gap: 6,
    },
    terminalCardSelected: {
        borderColor: '#8a4b2a',
        backgroundColor: '#fff6ef',
    },
    terminalHeader: {
        flexDirection: 'row',
        alignItems: 'center',
        justifyContent: 'space-between',
        gap: 12,
    },
    terminalTitle: {
        flex: 1,
        color: '#261f18',
        fontSize: 16,
        fontWeight: '700',
    },
    terminalBadge: {
        overflow: 'hidden',
        color: '#6c472f',
        fontSize: 12,
        fontWeight: '700',
        textTransform: 'uppercase',
        letterSpacing: 0.6,
    },
    terminalMeta: {
        color: '#5d5348',
        fontSize: 13,
        lineHeight: 18,
        fontFamily: 'monospace',
    },
    commandInput: {
        minHeight: 72,
        textAlignVertical: 'top',
    },
    terminalViewport: {
        minHeight: 280,
        maxHeight: 420,
        borderRadius: 16,
        borderWidth: 1,
        borderColor: '#d5c7b7',
        backgroundColor: '#17120f',
        overflow: 'hidden',
    },
    terminalViewportScroll: {
        flex: 1,
    },
    terminalContent: {
        color: '#f7efe5',
        fontSize: 13,
        lineHeight: 20,
        fontFamily: 'monospace',
        padding: 14,
    },
    terminalHint: {
        color: '#6e655b',
        fontSize: 13,
        lineHeight: 19,
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
    scannerHint: {
        color: '#d4c5b4',
        fontSize: 14,
        lineHeight: 21,
    },
});
