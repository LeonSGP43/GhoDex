import * as React from 'react';
import {
    ActivityIndicator,
    Modal,
    Pressable,
    ScrollView,
    StyleSheet,
    Text,
    TextInput,
    useWindowDimensions,
    View,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useRouter } from 'expo-router';
import { useFocusEffect } from '@react-navigation/native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { renderAnsiText } from '@/ghodex/ansi';
import {
    fetchSnapshot,
    readTerminal,
    runTerminalCommand,
    sendTerminalText,
    subscribeToGatewayEvents,
} from '@/ghodex/gateway';
import { INITIAL_GATEWAY_SESSION } from '@/ghodex/sessionState';
import { loadStoredSession, type StoredSession } from '@/ghodex/storage';
import { ActionButton, SurfaceCard } from '@/ghodex/ui';
import type {
    GatewayEnvelope,
    SnapshotResult,
    TerminalChangedRow,
    TerminalMutationResult,
    TerminalReadResult,
    TerminalRow,
} from '@/ghodex/types';

type BusyAction =
    | 'snapshot'
    | 'terminal-read'
    | 'terminal-command'
    | 'terminal-send-text'
    | null;

type LoadTerminalViewFn = (
    terminal: TerminalRow,
    authToken: string,
    options?: {
        expectedGeneration?: number;
        mode?: 'snapshot' | 'delta';
        sinceFrameId?: string;
        readAfterWriteId?: string;
    },
) => Promise<TerminalReadResult>;

type RefreshSnapshotFn = (
    authToken: string,
    preferredTerminalId: string | null,
) => Promise<SnapshotResult>;

const WRITE_SETTLE_ATTEMPTS = 6;
const WRITE_SETTLE_INTERVAL_MS = 250;

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

function isStructuralTerminalEvent(event: string | null | undefined): boolean {
    if (!event) {
        return false;
    }
    return event !== 'terminal.input.sent' && event !== 'terminal.command.sent';
}

function nextSequenceFromEnvelope(envelope: GatewayEnvelope): number | null {
    return typeof envelope.sequence === 'number' && Number.isFinite(envelope.sequence) ? envelope.sequence : null;
}

export default function GhoDexWorkspaceScreen() {
    const router = useRouter();
    const insets = useSafeAreaInsets();
    const { width } = useWindowDimensions();
    const [loaded, setLoaded] = React.useState(false);
    const [busyAction, setBusyAction] = React.useState<BusyAction>(null);
    const [errorMessage, setErrorMessage] = React.useState<string | null>(null);
    const [sidebarVisible, setSidebarVisible] = React.useState(false);
    const [subscriptionOpen, setSubscriptionOpen] = React.useState(false);
    const [session, setSession] = React.useState<StoredSession>(INITIAL_GATEWAY_SESSION);
    const [snapshot, setSnapshot] = React.useState<SnapshotResult | null>(null);
    const [selectedTerminalId, setSelectedTerminalId] = React.useState<string | null>(null);
    const [terminalView, setTerminalView] = React.useState<TerminalReadResult | null>(null);
    const [terminalContent, setTerminalContent] = React.useState('');
    const [terminalCommand, setTerminalCommand] = React.useState('');
    const sidebarWidth = Math.min(width * 0.84, 360);

    const selectedTerminal = React.useMemo(
        () => snapshot?.terminals.find((terminal) => terminal.terminalId === selectedTerminalId) ?? null,
        [selectedTerminalId, snapshot],
    );
    const paired = !!session.authToken.trim();
    const syncLabel = session.liveUpdatesEnabled
        ? (subscriptionOpen ? 'Live stream' : `Live reconnecting, ${session.pollIntervalMs}ms fallback`)
        : `${session.pollIntervalMs}ms polling`;

    const sessionRef = React.useRef(session);
    const snapshotRef = React.useRef<SnapshotResult | null>(snapshot);
    const selectedTerminalRef = React.useRef<TerminalRow | null>(selectedTerminal);
    const selectedTerminalIdRef = React.useRef<string | null>(selectedTerminalId);
    const terminalViewRef = React.useRef<TerminalReadResult | null>(terminalView);
    const subscriptionSequenceRef = React.useRef(0);
    const liveReadInFlightRef = React.useRef(false);
    const liveReadPendingRef = React.useRef(false);
    const snapshotRefreshTimerRef = React.useRef<ReturnType<typeof setTimeout> | null>(null);
    const loadTerminalViewRef = React.useRef<LoadTerminalViewFn | null>(null);
    const refreshSnapshotRef = React.useRef<RefreshSnapshotFn | null>(null);

    React.useEffect(() => {
        sessionRef.current = session;
    }, [session]);

    React.useEffect(() => {
        snapshotRef.current = snapshot;
        subscriptionSequenceRef.current = Math.max(subscriptionSequenceRef.current, snapshot?.lastSequence ?? 0);
    }, [snapshot]);

    React.useEffect(() => {
        selectedTerminalRef.current = selectedTerminal;
        selectedTerminalIdRef.current = selectedTerminalId;
    }, [selectedTerminal, selectedTerminalId]);

    React.useEffect(() => {
        terminalViewRef.current = terminalView;
        subscriptionSequenceRef.current = Math.max(subscriptionSequenceRef.current, terminalView?.lastSequence ?? 0);
    }, [terminalView]);

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

    const loadTerminalViewImpl = React.useCallback(async (
        terminal: TerminalRow,
        authToken: string,
        options?: {
            expectedGeneration?: number;
            mode?: 'snapshot' | 'delta';
            sinceFrameId?: string;
            readAfterWriteId?: string;
        },
    ) => {
        const activeSession = sessionRef.current;
        const result = await readTerminal({
            host: activeSession.host,
            port: activeSession.port,
            authToken,
            terminalId: terminal.terminalId,
            expectedGeneration: options?.expectedGeneration ?? terminal.generation,
            mode: options?.mode ?? 'snapshot',
            sinceFrameId: options?.sinceFrameId,
            maxChars: 24_000,
            maxLines: 300,
            readAfterWriteId: options?.readAfterWriteId,
        });

        const currentTerminalView = terminalViewRef.current;
        const expectsDelta = options?.mode === 'delta';
        const sameTerminal = currentTerminalView?.terminalId === result.terminalId;
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
                host: activeSession.host,
                port: activeSession.port,
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
    }, [applyTerminalResult]);

    React.useEffect(() => {
        loadTerminalViewRef.current = loadTerminalViewImpl;
    }, [loadTerminalViewImpl]);

    const refreshSnapshotImpl = React.useCallback(async (
        authToken: string,
        preferredTerminalId: string | null,
    ) => {
        const activeSession = sessionRef.current;
        const result = await fetchSnapshot({
            host: activeSession.host,
            port: activeSession.port,
            authToken,
        });
        setSnapshot(result);

        const nextTerminal = pickPreferredTerminal(result.terminals, preferredTerminalId);
        setSelectedTerminalId(nextTerminal?.terminalId ?? null);
        if (nextTerminal) {
            await loadTerminalViewImpl(nextTerminal, authToken);
        } else {
            setTerminalView(null);
            setTerminalContent('');
        }
        return result;
    }, [loadTerminalViewImpl]);

    React.useEffect(() => {
        refreshSnapshotRef.current = refreshSnapshotImpl;
    }, [refreshSnapshotImpl]);

    const settleTerminalAfterWrite = React.useCallback(async (
        terminal: TerminalRow,
        authToken: string,
        mutation: TerminalMutationResult,
    ) => {
        let sinceFrameId = terminalViewRef.current?.terminalId === terminal.terminalId
            ? terminalViewRef.current.frameId ?? undefined
            : undefined;

        for (let attempt = 0; attempt < WRITE_SETTLE_ATTEMPTS; attempt += 1) {
            if (attempt > 0) {
                await sleep(WRITE_SETTLE_INTERVAL_MS);
            }

            const result = await loadTerminalViewImpl(terminal, authToken, {
                expectedGeneration: mutation.generation,
                mode: sinceFrameId ? 'delta' : 'snapshot',
                sinceFrameId,
                readAfterWriteId: mutation.writeId ?? undefined,
            });

            sinceFrameId = result.frameId ?? sinceFrameId;
            const writeSettled = mutation.writeId
                ? result.readAfterReady === true
                : result.hasChanges;
            if (writeSettled) {
                return result;
            }
        }

        return loadTerminalViewImpl(terminal, authToken, {
            expectedGeneration: mutation.generation,
            readAfterWriteId: mutation.writeId ?? undefined,
        });
    }, [loadTerminalViewImpl]);

    const scheduleSnapshotRefresh = React.useCallback((reason?: string) => {
        if (snapshotRefreshTimerRef.current) {
            clearTimeout(snapshotRefreshTimerRef.current);
        }
        snapshotRefreshTimerRef.current = setTimeout(() => {
            snapshotRefreshTimerRef.current = null;
            const activeSession = sessionRef.current;
            const authToken = activeSession.authToken.trim();
            if (!authToken) {
                return;
            }
            void refreshSnapshotRef.current?.(authToken, selectedTerminalIdRef.current);
        }, reason === 'resync' ? 0 : 120);
    }, []);

    const driveSelectedTerminalFromSubscription = React.useCallback(() => {
        if (liveReadInFlightRef.current) {
            liveReadPendingRef.current = true;
            return;
        }

        const activeSession = sessionRef.current;
        const authToken = activeSession.authToken.trim();
        const currentTerminal = selectedTerminalRef.current;
        if (!authToken || !currentTerminal) {
            return;
        }

        liveReadInFlightRef.current = true;
        void (async () => {
            try {
                do {
                    liveReadPendingRef.current = false;
                    const currentView = terminalViewRef.current;
                    await loadTerminalViewRef.current?.(currentTerminal, authToken, {
                        expectedGeneration: currentView?.terminalId === currentTerminal.terminalId
                            ? currentView.generation
                            : currentTerminal.generation,
                        mode: currentView?.terminalId === currentTerminal.terminalId && currentView.frameId
                            ? 'delta'
                            : 'snapshot',
                        sinceFrameId: currentView?.terminalId === currentTerminal.terminalId
                            ? currentView.frameId ?? undefined
                            : undefined,
                    });
                } while (liveReadPendingRef.current);
            } catch (error) {
                console.warn('Failed to live-refresh terminal', error);
                scheduleSnapshotRefresh('resync');
            } finally {
                liveReadInFlightRef.current = false;
            }
        })();
    }, [scheduleSnapshotRefresh]);

    const handleSubscriptionEnvelope = React.useCallback((envelope: GatewayEnvelope) => {
        const result = envelope.result;
        if (envelope.status === 'ok' && result && typeof result === 'object') {
            const lastSequence = typeof result.last_sequence === 'number' ? result.last_sequence : null;
            if (lastSequence !== null) {
                subscriptionSequenceRef.current = Math.max(subscriptionSequenceRef.current, lastSequence);
            }
            setSubscriptionOpen(true);
            return;
        }

        const nextSequence = nextSequenceFromEnvelope(envelope);
        if (nextSequence !== null) {
            subscriptionSequenceRef.current = Math.max(subscriptionSequenceRef.current, nextSequence);
        }

        if (envelope.requires_snapshot_resync || envelope.gap) {
            scheduleSnapshotRefresh('resync');
            return;
        }

        const resource = envelope.resource;
        if (resource?.type !== 'terminal' || !resource.id) {
            return;
        }

        setSnapshot((current) => {
            if (!current) {
                return current;
            }
            return {
                ...current,
                lastSequence: Math.max(current.lastSequence, nextSequence ?? current.lastSequence),
                terminals: current.terminals.map((item) => (
                    item.terminalId === resource.id
                        ? {
                            ...item,
                            generation: Math.max(item.generation, resource.generation ?? item.generation),
                        }
                        : item
                )),
            };
        });

        if (resource.id === selectedTerminalIdRef.current) {
            driveSelectedTerminalFromSubscription();
            return;
        }

        if (isStructuralTerminalEvent(envelope.event)) {
            scheduleSnapshotRefresh('structure');
        }
    }, [driveSelectedTerminalFromSubscription, scheduleSnapshotRefresh]);

    const hydrateSession = React.useCallback(async () => {
        const stored = await loadStoredSession();
        setSession(stored);
        setLoaded(true);

        const authToken = stored.authToken.trim();
        if (!authToken) {
            setSnapshot(null);
            setSelectedTerminalId(null);
            setTerminalView(null);
            setTerminalContent('');
            setSubscriptionOpen(false);
            return;
        }

        await refreshSnapshotImpl(authToken, selectedTerminalIdRef.current);
    }, [refreshSnapshotImpl]);

    useFocusEffect(React.useCallback(() => {
        void hydrateSession();
        return () => {
            if (snapshotRefreshTimerRef.current) {
                clearTimeout(snapshotRefreshTimerRef.current);
                snapshotRefreshTimerRef.current = null;
            }
        };
    }, [hydrateSession]));

    const handleRefreshSnapshot = React.useCallback(() => {
        const authToken = session.authToken.trim();
        if (!authToken) {
            setErrorMessage('No auth token yet. Open pairing first.');
            return;
        }

        void runAction('snapshot', async () => {
            await refreshSnapshotImpl(authToken, selectedTerminalIdRef.current);
        });
    }, [refreshSnapshotImpl, runAction, session.authToken]);

    const handleSelectTerminal = React.useCallback((terminal: TerminalRow) => {
        const authToken = session.authToken.trim();
        if (!authToken) {
            setErrorMessage('No auth token yet. Open pairing first.');
            return;
        }

        setSelectedTerminalId(terminal.terminalId);
        setTerminalContent('');
        void runAction('terminal-read', async () => {
            await loadTerminalViewImpl(terminal, authToken);
        });
    }, [loadTerminalViewImpl, runAction, session.authToken]);

    const handleRefreshTerminal = React.useCallback(() => {
        if (!selectedTerminal) {
            setErrorMessage('Select a terminal first.');
            return;
        }

        void runAction('terminal-read', async () => {
            await loadTerminalViewImpl(
                selectedTerminal,
                session.authToken,
                terminalView?.terminalId === selectedTerminal.terminalId
                    ? { expectedGeneration: terminalView.generation, mode: 'snapshot' }
                    : undefined,
            );
        });
    }, [loadTerminalViewImpl, runAction, selectedTerminal, session.authToken, terminalView]);

    const handleSubmitInput = React.useCallback(() => {
        if (!selectedTerminal) {
            setErrorMessage('Select a terminal first.');
            return;
        }

        const rawInput = terminalCommand;
        const normalizedInput = rawInput.replace(/\r\n/g, '\n');
        if (!normalizedInput.trim()) {
            setErrorMessage('Input is empty.');
            return;
        }

        const expectsRawSend = normalizedInput.includes('\n');
        const action: BusyAction = expectsRawSend ? 'terminal-send-text' : 'terminal-command';

        void runAction(action, async () => {
            const expectedGeneration = terminalView?.terminalId === selectedTerminal.terminalId
                ? terminalView.generation
                : selectedTerminal.generation;
            const mutation = expectsRawSend
                ? await sendTerminalText({
                    host: session.host,
                    port: session.port,
                    authToken: session.authToken,
                    terminalId: selectedTerminal.terminalId,
                    text: rawInput,
                    expectedGeneration,
                })
                : await runTerminalCommand({
                    host: session.host,
                    port: session.port,
                    authToken: session.authToken,
                    terminalId: selectedTerminal.terminalId,
                    commandText: normalizedInput.trim(),
                    expectedGeneration,
                });
            setTerminalCommand('');
            await settleTerminalAfterWrite(selectedTerminal, session.authToken, mutation);
        });
    }, [runAction, selectedTerminal, session.authToken, session.host, session.port, settleTerminalAfterWrite, terminalCommand, terminalView]);

    React.useEffect(() => {
        const authToken = session.authToken.trim();
        if (!loaded || !authToken || !session.liveUpdatesEnabled) {
            setSubscriptionOpen(false);
            return;
        }

        let cancelled = false;
        let reconnectTimer: ReturnType<typeof setTimeout> | null = null;
        let unsubscribe: (() => void) | null = null;

        const openSubscription = () => {
            if (cancelled) {
                return;
            }

            try {
                unsubscribe = subscribeToGatewayEvents({
                    host: session.host,
                    port: session.port,
                    authToken,
                    sinceSequence: subscriptionSequenceRef.current,
                    eventLimit: 128,
                    onEnvelope: (envelope) => {
                        if (cancelled) {
                            return;
                        }
                        handleSubscriptionEnvelope(envelope);
                    },
                    onError: (error) => {
                        if (cancelled) {
                            return;
                        }
                        console.warn('Gateway subscription dropped', error);
                        setSubscriptionOpen(false);
                        reconnectTimer = setTimeout(openSubscription, Math.max(500, session.pollIntervalMs * 4));
                    },
                });
            } catch (error) {
                const message = error instanceof Error ? error.message : 'Failed to open gateway subscription';
                console.warn(message);
                setSubscriptionOpen(false);
                reconnectTimer = setTimeout(openSubscription, Math.max(500, session.pollIntervalMs * 4));
            }
        };

        openSubscription();

        return () => {
            cancelled = true;
            setSubscriptionOpen(false);
            if (reconnectTimer) {
                clearTimeout(reconnectTimer);
            }
            unsubscribe?.();
        };
    }, [handleSubscriptionEnvelope, loaded, session.authToken, session.host, session.liveUpdatesEnabled, session.pollIntervalMs, session.port]);

    React.useEffect(() => {
        const authToken = session.authToken.trim();
        if (!loaded || !authToken || !selectedTerminal) {
            return;
        }
        if (session.liveUpdatesEnabled && subscriptionOpen) {
            return;
        }

        let cancelled = false;
        let timer: ReturnType<typeof setTimeout> | null = null;

        const schedule = () => {
            if (cancelled) {
                return;
            }
            timer = setTimeout(tick, session.pollIntervalMs);
        };

        const tick = async () => {
            if (cancelled) {
                return;
            }
            if (busyAction || liveReadInFlightRef.current) {
                schedule();
                return;
            }

            liveReadInFlightRef.current = true;
            try {
                await loadTerminalViewImpl(selectedTerminal, authToken, {
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
                liveReadInFlightRef.current = false;
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
    }, [busyAction, loadTerminalViewImpl, loaded, selectedTerminal, session.authToken, session.liveUpdatesEnabled, session.pollIntervalMs, subscriptionOpen, terminalView]);

    const openPairing = React.useCallback(() => {
        setSidebarVisible(false);
        router.push('/pairing');
    }, [router]);

    const openSettings = React.useCallback(() => {
        setSidebarVisible(false);
        router.push('/gateway');
    }, [router]);

    if (!loaded) {
        return (
            <View style={styles.loadingScreen}>
                <ActivityIndicator size="large" color="#8a4b2a" />
                <Text style={styles.loadingText}>Loading GhoDex workspace…</Text>
            </View>
        );
    }

    const terminalDisplayText = selectedTerminal
        ? (terminalContent || 'No terminal text captured yet. Refresh the terminal to fetch the visible surface.')
        : 'Open the left sidebar and choose a terminal session.';

    return (
        <>
            <View style={styles.screen}>
                <View style={[styles.header, { paddingTop: insets.top + 10 }]}>
                    <WorkspaceIconButton icon="menu-outline" onPress={() => setSidebarVisible(true)} />
                    <View style={styles.headerCopy}>
                        <Text numberOfLines={1} style={styles.headerTitle}>
                            {selectedTerminal?.title || (paired ? 'Choose terminal' : 'GhoDex Remote')}
                        </Text>
                        <Text numberOfLines={1} style={styles.headerSubtitle}>
                            {selectedTerminal?.workingDirectory || syncLabel}
                        </Text>
                    </View>
                    <WorkspaceIconButton
                        disabled={!paired || busyAction === 'snapshot'}
                        icon="refresh-outline"
                        onPress={handleRefreshSnapshot}
                    />
                </View>

                {errorMessage ? (
                    <View style={styles.errorBar}>
                        <Ionicons color="#a9412b" name="alert-circle-outline" size={16} />
                        <Text numberOfLines={2} style={styles.errorText}>{errorMessage}</Text>
                    </View>
                ) : null}

                <View style={styles.workspaceStage}>
                    {!paired ? (
                        <View style={styles.emptyStage}>
                            <SurfaceCard title="Pair your desktop first" subtitle="The home screen now stays focused on the terminal panel. Pairing and sync settings moved into the left sidebar.">
                                <View style={styles.emptyActions}>
                                    <ActionButton label="Open Pairing" onPress={openPairing} />
                                    <ActionButton kind="secondary" label="Settings" onPress={openSettings} />
                                </View>
                            </SurfaceCard>
                        </View>
                    ) : (
                        <View style={styles.terminalShell}>
                            <View style={styles.terminalToolbar}>
                                <Text numberOfLines={1} style={styles.terminalToolbarPath}>
                                    {selectedTerminal?.workingDirectory || 'Select a terminal from the sidebar'}
                                </Text>
                                <View style={styles.terminalToolbarActions}>
                                    <SyncBadge live={session.liveUpdatesEnabled} open={subscriptionOpen} pollIntervalMs={session.pollIntervalMs} />
                                    <WorkspaceMiniAction
                                        busy={busyAction === 'terminal-read'}
                                        icon="sync-outline"
                                        label="Refresh"
                                        onPress={handleRefreshTerminal}
                                    />
                                </View>
                            </View>

                            <View style={styles.terminalViewport}>
                                <ScrollView nestedScrollEnabled style={styles.terminalScroll}>
                                    <Text selectable style={styles.terminalContent}>
                                        {renderAnsiText(terminalDisplayText)}
                                    </Text>
                                </ScrollView>
                            </View>
                        </View>
                    )}
                </View>

                {paired ? (
                    <View style={[styles.commandDock, { paddingBottom: Math.max(insets.bottom, 12) }]}>
                        <TextInput
                            autoCapitalize="none"
                            autoCorrect={false}
                            multiline
                            onChangeText={setTerminalCommand}
                            placeholder="Single line executes. Multiline text sends raw input."
                            placeholderTextColor="#8f867a"
                            style={styles.commandInput}
                            value={terminalCommand}
                        />
                        <View style={styles.commandFooter}>
                            <Text style={styles.commandHint}>
                                Single-line input runs as a command. Multi-line input is pasted as raw terminal text.
                            </Text>
                            <View style={styles.commandActions}>
                                <ActionButton
                                    busy={busyAction === 'terminal-command' || busyAction === 'terminal-send-text'}
                                    label={terminalCommand.includes('\n') ? 'Paste Raw' : 'Send'}
                                    onPress={handleSubmitInput}
                                />
                            </View>
                        </View>
                    </View>
                ) : null}
            </View>

            <Modal
                animationType="fade"
                onRequestClose={() => setSidebarVisible(false)}
                transparent
                visible={sidebarVisible}
            >
                <View style={styles.sidebarOverlay}>
                    <View style={[styles.sidebarPanel, { paddingTop: insets.top + 12, paddingBottom: Math.max(insets.bottom, 16), width: sidebarWidth }]}>
                        <View style={styles.sidebarHeader}>
                            <View style={styles.sidebarHeaderCopy}>
                                <Text style={styles.sidebarTitle}>GhoDex</Text>
                                <Text style={styles.sidebarSubtitle}>
                                    {paired ? `${snapshot?.terminals.length ?? 0} terminal sessions` : 'No active pairing yet'}
                                </Text>
                            </View>
                            <WorkspaceIconButton icon="close-outline" onPress={() => setSidebarVisible(false)} />
                        </View>

                        <Text style={styles.sidebarSectionTitle}>Terminal Sessions</Text>
                        <ScrollView contentContainerStyle={styles.sidebarList} showsVerticalScrollIndicator={false} style={styles.sidebarScroll}>
                            {paired && snapshot?.terminals.length ? snapshot.terminals.map((terminal) => (
                                <Pressable
                                    key={terminal.terminalId}
                                    onPress={() => {
                                        setSidebarVisible(false);
                                        handleSelectTerminal(terminal);
                                    }}
                                    style={({ pressed }) => [
                                        styles.sidebarTerminalItem,
                                        terminal.terminalId === selectedTerminalId ? styles.sidebarTerminalItemActive : null,
                                        pressed ? styles.sidebarTerminalItemPressed : null,
                                    ]}
                                >
                                    <Text numberOfLines={1} style={[
                                        styles.sidebarTerminalTitle,
                                        terminal.terminalId === selectedTerminalId ? styles.sidebarTerminalTitleActive : null,
                                    ]}>
                                        {terminal.title || terminal.terminalId.slice(0, 8)}
                                    </Text>
                                    <Text numberOfLines={2} style={[
                                        styles.sidebarTerminalMeta,
                                        terminal.terminalId === selectedTerminalId ? styles.sidebarTerminalMetaActive : null,
                                    ]}>
                                        {terminal.workingDirectory || terminal.terminalId}
                                    </Text>
                                </Pressable>
                            )) : (
                                <View style={styles.sidebarEmpty}>
                                    <Text style={styles.sidebarEmptyTitle}>No terminal data yet</Text>
                                    <Text style={styles.sidebarEmptyText}>
                                        Pair the phone first, then reopen the sidebar to switch between desktop terminal sessions.
                                    </Text>
                                </View>
                            )}
                        </ScrollView>

                        <View style={styles.sidebarFooter}>
                            <SidebarLink icon="qr-code-outline" label="Pair Device" onPress={openPairing} />
                            <SidebarLink icon="settings-outline" label="Settings" onPress={openSettings} />
                            <SidebarLink icon="refresh-outline" label="Refresh Sessions" onPress={() => {
                                setSidebarVisible(false);
                                handleRefreshSnapshot();
                            }}
                            />
                            <View style={styles.sidebarStatus}>
                                <Text style={styles.sidebarStatusLine}>{session.host}:{session.port}</Text>
                                <Text style={styles.sidebarStatusLine}>{syncLabel}</Text>
                            </View>
                        </View>
                    </View>
                    <Pressable onPress={() => setSidebarVisible(false)} style={styles.sidebarBackdrop} />
                </View>
            </Modal>
        </>
    );
}

function WorkspaceIconButton(props: {
    disabled?: boolean;
    icon: keyof typeof Ionicons.glyphMap;
    onPress: () => void;
}) {
    return (
        <Pressable
            disabled={props.disabled}
            onPress={props.onPress}
            style={({ pressed }) => [
                styles.iconButton,
                pressed ? styles.iconButtonPressed : null,
                props.disabled ? styles.iconButtonDisabled : null,
            ]}
        >
            <Ionicons color="#f6eee3" name={props.icon} size={22} />
        </Pressable>
    );
}

function WorkspaceMiniAction(props: {
    busy?: boolean;
    icon: keyof typeof Ionicons.glyphMap;
    label: string;
    onPress: () => void;
}) {
    return (
        <Pressable
            disabled={props.busy}
            onPress={props.onPress}
            style={({ pressed }) => [
                styles.miniAction,
                pressed ? styles.sidebarTerminalItemPressed : null,
                props.busy ? styles.iconButtonDisabled : null,
            ]}
        >
            {props.busy ? <ActivityIndicator color="#d9b68f" size="small" /> : <Ionicons color="#d9b68f" name={props.icon} size={15} />}
            <Text style={styles.miniActionText}>{props.label}</Text>
        </Pressable>
    );
}

function SidebarLink(props: {
    icon: keyof typeof Ionicons.glyphMap;
    label: string;
    onPress: () => void;
}) {
    return (
        <Pressable onPress={props.onPress} style={({ pressed }) => [styles.sidebarLink, pressed ? styles.sidebarTerminalItemPressed : null]}>
            <Ionicons color="#fff4e7" name={props.icon} size={18} />
            <Text style={styles.sidebarLinkText}>{props.label}</Text>
            <Ionicons color="#c6b39b" name="chevron-forward-outline" size={18} />
        </Pressable>
    );
}

function SyncBadge(props: {
    live: boolean;
    open: boolean;
    pollIntervalMs: number;
}) {
    const label = props.live
        ? (props.open ? 'Live' : 'Reconnecting')
        : `${props.pollIntervalMs}ms`;
    return (
        <View style={[
            styles.syncBadge,
            props.live && props.open ? styles.syncBadgeLive : null,
        ]}>
            <Text style={styles.syncBadgeText}>{label}</Text>
        </View>
    );
}

const styles = StyleSheet.create({
    screen: {
        flex: 1,
        backgroundColor: '#100d0b',
    },
    loadingScreen: {
        flex: 1,
        alignItems: 'center',
        justifyContent: 'center',
        gap: 12,
        backgroundColor: '#100d0b',
    },
    loadingText: {
        color: '#d7c8b8',
        fontSize: 16,
    },
    header: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: 12,
        paddingHorizontal: 16,
        paddingBottom: 14,
        backgroundColor: '#171210',
        borderBottomWidth: 1,
        borderBottomColor: '#2a211b',
    },
    headerCopy: {
        flex: 1,
        gap: 2,
    },
    headerTitle: {
        color: '#fff7ed',
        fontSize: 17,
        fontWeight: '700',
    },
    headerSubtitle: {
        color: '#ad9d8b',
        fontSize: 12,
        lineHeight: 17,
    },
    iconButton: {
        width: 40,
        height: 40,
        borderRadius: 14,
        alignItems: 'center',
        justifyContent: 'center',
        backgroundColor: '#2a211b',
    },
    iconButtonPressed: {
        opacity: 0.82,
    },
    iconButtonDisabled: {
        opacity: 0.45,
    },
    errorBar: {
        marginHorizontal: 16,
        marginTop: 12,
        paddingHorizontal: 12,
        paddingVertical: 10,
        borderRadius: 14,
        borderWidth: 1,
        borderColor: '#6a2d21',
        backgroundColor: '#321712',
        flexDirection: 'row',
        alignItems: 'flex-start',
        gap: 8,
    },
    errorText: {
        flex: 1,
        color: '#f0c0b6',
        fontSize: 13,
        lineHeight: 18,
    },
    workspaceStage: {
        flex: 1,
        minHeight: 0,
        paddingHorizontal: 16,
        paddingTop: 12,
        paddingBottom: 12,
    },
    emptyStage: {
        flex: 1,
        justifyContent: 'center',
    },
    emptyActions: {
        flexDirection: 'row',
        gap: 12,
    },
    terminalShell: {
        flex: 1,
        minHeight: 0,
        borderRadius: 24,
        borderWidth: 1,
        borderColor: '#2e241d',
        backgroundColor: '#0c0907',
        overflow: 'hidden',
    },
    terminalToolbar: {
        flexDirection: 'row',
        alignItems: 'center',
        justifyContent: 'space-between',
        gap: 12,
        paddingHorizontal: 14,
        paddingVertical: 12,
        borderBottomWidth: 1,
        borderBottomColor: '#221b16',
        backgroundColor: '#16110f',
    },
    terminalToolbarPath: {
        flex: 1,
        color: '#b8a894',
        fontSize: 12,
        lineHeight: 17,
        fontFamily: 'monospace',
    },
    terminalToolbarActions: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: 8,
    },
    miniAction: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: 6,
        paddingHorizontal: 10,
        paddingVertical: 8,
        borderRadius: 12,
        backgroundColor: '#251d18',
    },
    miniActionText: {
        color: '#d9b68f',
        fontSize: 12,
        fontWeight: '700',
    },
    syncBadge: {
        borderRadius: 999,
        paddingHorizontal: 10,
        paddingVertical: 7,
        backgroundColor: '#251d18',
    },
    syncBadgeLive: {
        backgroundColor: '#173225',
    },
    syncBadgeText: {
        color: '#d8c6b2',
        fontSize: 11,
        fontWeight: '700',
        textTransform: 'uppercase',
        letterSpacing: 0.5,
    },
    terminalViewport: {
        flex: 1,
        minHeight: 0,
    },
    terminalScroll: {
        flex: 1,
    },
    terminalContent: {
        padding: 16,
        color: '#f8efe3',
        fontSize: 14,
        lineHeight: 22,
        fontFamily: 'monospace',
    },
    commandDock: {
        paddingHorizontal: 16,
        paddingTop: 12,
        backgroundColor: '#171210',
        borderTopWidth: 1,
        borderTopColor: '#2a211b',
        gap: 10,
    },
    commandInput: {
        minHeight: 86,
        maxHeight: 160,
        borderRadius: 18,
        backgroundColor: '#221b16',
        borderWidth: 1,
        borderColor: '#342921',
        paddingHorizontal: 14,
        paddingVertical: 12,
        color: '#fff7ed',
        fontSize: 15,
        textAlignVertical: 'top',
        fontFamily: 'monospace',
    },
    commandFooter: {
        flexDirection: 'row',
        alignItems: 'flex-start',
        gap: 12,
    },
    commandHint: {
        flex: 1,
        color: '#a8937d',
        fontSize: 12,
        lineHeight: 17,
    },
    commandActions: {
        minWidth: 132,
    },
    sidebarOverlay: {
        flex: 1,
        flexDirection: 'row',
        backgroundColor: 'rgba(0, 0, 0, 0.45)',
    },
    sidebarPanel: {
        backgroundColor: '#191411',
        borderRightWidth: 1,
        borderRightColor: '#2d241d',
        paddingHorizontal: 14,
        gap: 14,
    },
    sidebarBackdrop: {
        flex: 1,
    },
    sidebarHeader: {
        flexDirection: 'row',
        alignItems: 'center',
        justifyContent: 'space-between',
        gap: 12,
    },
    sidebarHeaderCopy: {
        flex: 1,
        gap: 4,
    },
    sidebarTitle: {
        color: '#fff6eb',
        fontSize: 22,
        fontWeight: '800',
    },
    sidebarSubtitle: {
        color: '#b19f8b',
        fontSize: 13,
        lineHeight: 18,
    },
    sidebarSectionTitle: {
        color: '#7d6d5d',
        fontSize: 11,
        fontWeight: '700',
        letterSpacing: 0.8,
        textTransform: 'uppercase',
    },
    sidebarScroll: {
        flex: 1,
    },
    sidebarList: {
        gap: 10,
        paddingBottom: 8,
    },
    sidebarTerminalItem: {
        borderRadius: 18,
        paddingHorizontal: 14,
        paddingVertical: 14,
        backgroundColor: '#241d18',
        gap: 6,
    },
    sidebarTerminalItemActive: {
        backgroundColor: '#8a4b2a',
    },
    sidebarTerminalItemPressed: {
        opacity: 0.82,
    },
    sidebarTerminalTitle: {
        color: '#f8efe3',
        fontSize: 15,
        fontWeight: '700',
    },
    sidebarTerminalTitleActive: {
        color: '#fff9f0',
    },
    sidebarTerminalMeta: {
        color: '#b7a490',
        fontSize: 12,
        lineHeight: 18,
        fontFamily: 'monospace',
    },
    sidebarTerminalMetaActive: {
        color: '#f5decc',
    },
    sidebarEmpty: {
        borderRadius: 18,
        paddingHorizontal: 14,
        paddingVertical: 16,
        backgroundColor: '#241d18',
        gap: 8,
    },
    sidebarEmptyTitle: {
        color: '#fff4e7',
        fontSize: 15,
        fontWeight: '700',
    },
    sidebarEmptyText: {
        color: '#b7a490',
        fontSize: 13,
        lineHeight: 19,
    },
    sidebarFooter: {
        gap: 10,
        paddingTop: 6,
    },
    sidebarLink: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: 10,
        borderRadius: 16,
        backgroundColor: '#241d18',
        paddingHorizontal: 14,
        paddingVertical: 13,
    },
    sidebarLinkText: {
        flex: 1,
        color: '#fff4e7',
        fontSize: 14,
        fontWeight: '700',
    },
    sidebarStatus: {
        borderRadius: 16,
        backgroundColor: '#130f0c',
        paddingHorizontal: 14,
        paddingVertical: 12,
        gap: 4,
    },
    sidebarStatusLine: {
        color: '#9f8f7d',
        fontSize: 12,
        lineHeight: 17,
        fontFamily: 'monospace',
    },
});
