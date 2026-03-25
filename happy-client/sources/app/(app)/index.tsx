import * as React from 'react';
import {
    ActivityIndicator,
    Alert,
    Animated,
    Easing,
    Platform,
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
import { KeyboardAvoidingView } from 'react-native-keyboard-controller';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { renderAnsiText } from '@/ghodex/ansi';
import {
    closeTab as closeGatewayTab,
    createTab as createGatewayTab,
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
    TabRow,
    TerminalChangedRow,
    TerminalMutationResult,
    TerminalReadResult,
    TerminalRow,
} from '@/ghodex/types';

type BusyAction =
    | 'snapshot'
    | 'tab-create'
    | 'tab-close'
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

function pickPreferredTerminalInTab(tab: TabRow): TerminalRow | null {
    return tab.terminals.find((terminal) => terminal.focused) ?? tab.terminals[0] ?? null;
}

function normalizeSidebarLabel(value: string | null | undefined): string {
    return (value ?? '').trim().replace(/\s+/g, ' ').toLowerCase();
}

function labelsMatch(left: string | null | undefined, right: string | null | undefined): boolean {
    const normalizedLeft = normalizeSidebarLabel(left);
    const normalizedRight = normalizeSidebarLabel(right);
    return normalizedLeft.length > 0 && normalizedLeft === normalizedRight;
}

function tabHasDistinctTitle(tab: TabRow): boolean {
    const tabTitle = tab.title?.trim();
    if (!tabTitle) {
        return false;
    }

    return !tab.terminals.some((terminal) => labelsMatch(tabTitle, terminal.title));
}

function fallbackTabLabel(tab: TabRow): string {
    return tab.windowNumber > 0 ? `Tab ${tab.windowNumber}` : 'Tab';
}

function tabPrimaryLabel(tab: TabRow, preferredTerminal: TerminalRow | null): string {
    const tabTitle = tab.title?.trim();
    const terminalTitle = preferredTerminal?.title?.trim();

    if (tab.terminals.length > 1) {
        if (tabHasDistinctTitle(tab) && tabTitle) {
            return tabTitle;
        }
        return fallbackTabLabel(tab);
    }

    if (tabTitle && !labelsMatch(tabTitle, terminalTitle)) {
        return tabTitle;
    }
    if (terminalTitle) {
        return terminalTitle;
    }
    if (tabTitle) {
        return tabTitle;
    }
    return fallbackTabLabel(tab);
}

function tabSecondaryLabel(tab: TabRow, preferredTerminal: TerminalRow | null, primaryLabel: string): string | null {
    if (tab.terminals.length > 1) {
        return `${tab.terminals.length} terminals`;
    }

    const tabTitle = tab.title?.trim();
    const terminalTitle = preferredTerminal?.title?.trim();
    const workingDirectory = preferredTerminal?.workingDirectory?.trim();
    if (
        workingDirectory
        && !labelsMatch(workingDirectory, primaryLabel)
        && !labelsMatch(workingDirectory, terminalTitle)
        && !labelsMatch(workingDirectory, tabTitle)
    ) {
        return workingDirectory;
    }

    if (
        terminalTitle
        && !labelsMatch(terminalTitle, primaryLabel)
        && !labelsMatch(terminalTitle, tabTitle)
    ) {
        return terminalTitle;
    }

    if (
        tabTitle
        && !labelsMatch(tabTitle, primaryLabel)
        && !labelsMatch(tabTitle, terminalTitle)
    ) {
        return tabTitle;
    }

    return null;
}

function terminalMetaLabel(terminal: TerminalRow): string {
    const workingDirectory = terminal.workingDirectory?.trim();
    if (workingDirectory && !labelsMatch(workingDirectory, terminal.title)) {
        return workingDirectory;
    }
    return terminal.terminalId;
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

function isGatewayAuthError(error: unknown): boolean {
    return !!(
        error
        && typeof error === 'object'
        && 'code' in error
        && (error as { code?: unknown }).code === 'unauthorized'
    );
}

function isRecoverableTabCloseError(error: unknown): boolean {
    return !!(
        error
        && typeof error === 'object'
        && 'code' in error
        && (
            (error as { code?: unknown }).code === 'stale_target'
            || (error as { code?: unknown }).code === 'tab_not_found'
        )
    );
}

function normalizeCommandInput(input: string): string {
    return input
        .replace(/\r\n?/g, '\n')
        .replace(/[\u2028\u2029]/g, '\n');
}

function shouldPasteRawInput(input: string): boolean {
    const trimmed = normalizeCommandInput(input).trim();
    return trimmed.includes('\n');
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
    const [authorizationRequired, setAuthorizationRequired] = React.useState(false);
    const [session, setSession] = React.useState<StoredSession>(INITIAL_GATEWAY_SESSION);
    const [snapshot, setSnapshot] = React.useState<SnapshotResult | null>(null);
    const [selectedTerminalId, setSelectedTerminalId] = React.useState<string | null>(null);
    const [terminalView, setTerminalView] = React.useState<TerminalReadResult | null>(null);
    const [terminalContent, setTerminalContent] = React.useState('');
    const [terminalCommand, setTerminalCommand] = React.useState('');
    const sidebarWidth = Math.min(width * 0.84, 360);
    const sidebarProgress = React.useRef(new Animated.Value(0)).current;

    const selectedTerminal = React.useMemo(
        () => snapshot?.terminals.find((terminal) => terminal.terminalId === selectedTerminalId) ?? null,
        [selectedTerminalId, snapshot],
    );
    const selectedTab = React.useMemo(() => {
        if (selectedTerminal?.tabId) {
            return snapshot?.tabs.find((tab) => tab.tabId === selectedTerminal.tabId) ?? null;
        }
        return snapshot?.tabs.find((tab) => tab.focused) ?? snapshot?.tabs[0] ?? null;
    }, [selectedTerminal, snapshot]);
    const paired = !!session.authToken.trim();
    const tabCount = snapshot?.tabs.length ?? 0;
    const terminalCount = snapshot?.terminals.length ?? 0;
    const syncLabel = session.liveUpdatesEnabled
        ? (subscriptionOpen ? 'Live stream' : `Live reconnecting, ${session.pollIntervalMs}ms fallback`)
        : `${session.pollIntervalMs}ms polling`;
    const sidebarTranslateX = React.useMemo(() => (
        sidebarProgress.interpolate({
            inputRange: [0, 1],
            outputRange: [-sidebarWidth, 0],
        })
    ), [sidebarProgress, sidebarWidth]);
    const contentTranslateX = React.useMemo(() => (
        sidebarProgress.interpolate({
            inputRange: [0, 1],
            outputRange: [0, sidebarWidth],
        })
    ), [sidebarProgress, sidebarWidth]);
    const contentScale = React.useMemo(() => (
        sidebarProgress.interpolate({
            inputRange: [0, 1],
            outputRange: [1, 0.98],
        })
    ), [sidebarProgress]);
    const backdropOpacity = React.useMemo(() => (
        sidebarProgress.interpolate({
            inputRange: [0, 1],
            outputRange: [0, 1],
        })
    ), [sidebarProgress]);

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
        if (!session.authToken.trim()) {
            setAuthorizationRequired(false);
        }
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

    React.useEffect(() => {
        Animated.timing(sidebarProgress, {
            toValue: sidebarVisible ? 1 : 0,
            duration: sidebarVisible ? 240 : 200,
            easing: sidebarVisible ? Easing.out(Easing.cubic) : Easing.inOut(Easing.quad),
            useNativeDriver: true,
        }).start();
    }, [sidebarProgress, sidebarVisible]);

    const runAction = React.useCallback(async (action: BusyAction, task: () => Promise<void>) => {
        setBusyAction(action);
        setErrorMessage(null);
        try {
            await task();
            setAuthorizationRequired(false);
        } catch (error) {
            const message = error instanceof Error ? error.message : 'Unexpected gateway error';
            if (isGatewayAuthError(error)) {
                setAuthorizationRequired(true);
                setSubscriptionOpen(false);
                setErrorMessage('Gateway authorization expired for this desktop build. Re-open Pairing in Settings and bind the phone again.');
                return;
            }
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
                tabs: current.tabs.map((tab) => ({
                    ...tab,
                    terminals: tab.terminals.map((item) => (
                        item.terminalId === result.terminalId
                            ? { ...item, generation: result.generation }
                            : item
                    )),
                })),
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
        setAuthorizationRequired(false);
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
                if (isGatewayAuthError(error)) {
                    setAuthorizationRequired(true);
                    setSubscriptionOpen(false);
                    setErrorMessage('Gateway authorization expired for this desktop build. Re-open Pairing in Settings and bind the phone again.');
                    return;
                }
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
        if (resource?.type === 'tab') {
            scheduleSnapshotRefresh('structure');
            return;
        }

        if (resource?.type !== 'terminal' || !resource.id) {
            if (isStructuralTerminalEvent(envelope.event)) {
                scheduleSnapshotRefresh('structure');
            }
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
            setAuthorizationRequired(false);
            return;
        }

        try {
            await refreshSnapshotImpl(authToken, selectedTerminalIdRef.current);
        } catch (error) {
            if (isGatewayAuthError(error)) {
                setAuthorizationRequired(true);
                setSubscriptionOpen(false);
                setErrorMessage('Gateway authorization expired for this desktop build. Re-open Pairing in Settings and bind the phone again.');
                return;
            }
            const message = error instanceof Error ? error.message : 'Failed to load gateway snapshot';
            setErrorMessage(message);
        }
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

    const handleSelectTab = React.useCallback((tab: TabRow) => {
        const preferredTerminal = pickPreferredTerminalInTab(tab);
        if (!preferredTerminal) {
            setErrorMessage('This tab does not expose any remote terminal yet.');
            return;
        }
        handleSelectTerminal(preferredTerminal);
    }, [handleSelectTerminal]);

    const handleCreateTab = React.useCallback(() => {
        const authToken = session.authToken.trim();
        if (!authToken) {
            setErrorMessage('No auth token yet. Open pairing first.');
            return;
        }

        void runAction('tab-create', async () => {
            const result = await createGatewayTab({
                host: session.host,
                port: session.port,
                authToken,
                parentTabId: selectedTab?.tabId,
                workingDirectory: selectedTerminal?.workingDirectory ?? undefined,
            });
            await refreshSnapshotImpl(authToken, result.terminalId ?? selectedTerminalIdRef.current);
            setSidebarVisible(false);
        });
    }, [refreshSnapshotImpl, runAction, selectedTab, selectedTerminal, session.authToken, session.host, session.port]);

    const handleCloseTab = React.useCallback((tab: TabRow) => {
        const authToken = session.authToken.trim();
        if (!authToken) {
            setErrorMessage('No auth token yet. Open pairing first.');
            return;
        }

        Alert.alert(
            'Close tab on phone?',
            'This confirmation belongs to the phone side. If the tab still has a running process, confirming here will force close it on the desktop without showing a second desktop popup.',
            [
                { text: 'Cancel', style: 'cancel' },
                {
                    text: 'Close Tab',
                    style: 'destructive',
                    onPress: () => {
                        void runAction('tab-close', async () => {
                            try {
                                await closeGatewayTab({
                                    host: session.host,
                                    port: session.port,
                                    authToken,
                                    tabId: tab.tabId,
                                    expectedGeneration: tab.generation,
                                    force: true,
                                });
                            } catch (error) {
                                if (isRecoverableTabCloseError(error)) {
                                    await refreshSnapshotImpl(authToken, selectedTerminalIdRef.current);
                                    setErrorMessage('The tab changed on desktop before the phone finished closing it. The phone view has been resynced.');
                                    return;
                                }
                                throw error;
                            }

                            await refreshSnapshotImpl(authToken, selectedTerminalIdRef.current);
                        });
                    },
                },
            ],
        );
    }, [refreshSnapshotImpl, runAction, session.authToken, session.host, session.port]);

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
        const normalizedInput = normalizeCommandInput(rawInput);
        if (!normalizedInput.trim()) {
            setErrorMessage('Input is empty.');
            return;
        }

        const expectsRawSend = shouldPasteRawInput(normalizedInput);
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
        if (!loaded || !authToken || !session.liveUpdatesEnabled || authorizationRequired) {
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
                        if (isGatewayAuthError(error)) {
                            setAuthorizationRequired(true);
                            setSubscriptionOpen(false);
                            setErrorMessage('Gateway authorization expired for this desktop build. Re-open Pairing in Settings and bind the phone again.');
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
    }, [authorizationRequired, handleSubscriptionEnvelope, loaded, session.authToken, session.host, session.liveUpdatesEnabled, session.pollIntervalMs, session.port]);

    React.useEffect(() => {
        const authToken = session.authToken.trim();
        if (!loaded || !authToken || !selectedTerminal || authorizationRequired) {
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
                if (isGatewayAuthError(error)) {
                    setAuthorizationRequired(true);
                    setSubscriptionOpen(false);
                    setErrorMessage('Gateway authorization expired for this desktop build. Re-open Pairing in Settings and bind the phone again.');
                    return;
                }
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
    }, [authorizationRequired, busyAction, loadTerminalViewImpl, loaded, selectedTerminal, session.authToken, session.liveUpdatesEnabled, session.pollIntervalMs, subscriptionOpen, terminalView]);

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
        <View style={styles.screen}>
            <Animated.View
                pointerEvents={sidebarVisible ? 'auto' : 'none'}
                style={[
                    styles.sidebarPanel,
                    {
                        paddingTop: insets.top + 12,
                        paddingBottom: Math.max(insets.bottom, 16),
                        transform: [{ translateX: sidebarTranslateX }],
                        width: sidebarWidth,
                    },
                ]}
            >
                <View style={styles.sidebarHeader}>
                    <View style={styles.sidebarHeaderCopy}>
                        <Text style={styles.sidebarTitle}>GhoDex</Text>
                        <Text style={styles.sidebarSubtitle}>
                            {paired ? `${tabCount} tabs, ${terminalCount} terminals` : 'No active pairing yet'}
                        </Text>
                    </View>
                    <WorkspaceIconButton
                        disabled={busyAction === 'tab-create'}
                        icon="add-outline"
                        onPress={handleCreateTab}
                    />
                </View>

                <Text style={styles.sidebarSectionTitle}>Workspace Tabs</Text>
                <ScrollView contentContainerStyle={styles.sidebarList} showsVerticalScrollIndicator={false} style={styles.sidebarScroll}>
                    {paired && snapshot?.tabs.length ? snapshot.tabs.map((tab) => {
                        const preferredTerminal = pickPreferredTerminalInTab(tab);
                        const tabActive = tab.tabId === selectedTab?.tabId;
                        const showTerminalList = tab.terminals.length > 1;
                        const primaryLabel = tabPrimaryLabel(tab, preferredTerminal);
                        const secondaryLabel = tabSecondaryLabel(tab, preferredTerminal, primaryLabel);

                        return (
                            <View
                                key={tab.tabId}
                                style={[
                                    styles.sidebarTabCard,
                                    tabActive ? styles.sidebarTabCardActive : null,
                                ]}
                            >
                                <View style={styles.sidebarTabHeader}>
                                    <Pressable
                                        onPress={() => {
                                            if (preferredTerminal) {
                                                setSidebarVisible(false);
                                                handleSelectTab(tab);
                                            }
                                        }}
                                        style={({ pressed }) => [
                                            styles.sidebarTabInfo,
                                            pressed ? styles.sidebarTerminalItemPressed : null,
                                        ]}
                                    >
                                        <Text numberOfLines={1} style={[
                                            styles.sidebarTabTitle,
                                            tabActive ? styles.sidebarTabTitleActive : null,
                                        ]}>
                                            {primaryLabel}
                                        </Text>
                                        {secondaryLabel ? (
                                            <Text numberOfLines={1} style={[
                                                styles.sidebarTabMeta,
                                                tabActive ? styles.sidebarTabMetaActive : null,
                                            ]}>
                                                {secondaryLabel}
                                            </Text>
                                        ) : null}
                                    </Pressable>
                                    <Pressable
                                        hitSlop={8}
                                        onPress={() => handleCloseTab(tab)}
                                        style={({ pressed }) => [
                                            styles.sidebarTabCloseButton,
                                            pressed ? styles.sidebarTerminalItemPressed : null,
                                        ]}
                                    >
                                        <Ionicons color="#d8b18e" name="close-outline" size={18} />
                                    </Pressable>
                                </View>

                                {showTerminalList ? (
                                    <View style={styles.sidebarTabTerminalList}>
                                        {tab.terminals.map((terminal) => (
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
                                                    {terminalMetaLabel(terminal)}
                                                </Text>
                                            </Pressable>
                                        ))}
                                    </View>
                                ) : null}
                            </View>
                        );
                    }) : (
                        <View style={styles.sidebarEmpty}>
                            <Text style={styles.sidebarEmptyTitle}>No tab data yet</Text>
                            <Text style={styles.sidebarEmptyText}>
                                Pair the phone first, then reopen the sidebar to manage desktop tabs and switch terminal sessions.
                            </Text>
                        </View>
                    )}
                </ScrollView>

                <View style={styles.sidebarFooter}>
                    <View style={styles.sidebarQuickRow}>
                        <SidebarQuickAction icon="qr-code-outline" label="Device" onPress={openPairing} />
                        <SidebarQuickAction icon="settings-outline" label="Settings" onPress={openSettings} />
                    </View>
                    <View style={styles.sidebarStatus}>
                        <Text style={styles.sidebarStatusLine}>{session.host}:{session.port}</Text>
                        <Text style={styles.sidebarStatusLine}>{syncLabel}</Text>
                    </View>
                </View>
            </Animated.View>

            <Animated.View
                style={[
                    styles.mainShell,
                    {
                        transform: [
                            { translateX: contentTranslateX },
                            { scale: contentScale },
                        ],
                    },
                ]}
            >
                <View style={[styles.header, { paddingTop: insets.top + 10 }]}>
                    <WorkspaceIconButton icon="menu-outline" onPress={() => setSidebarVisible((current) => !current)} />
                    <View style={styles.headerCopy}>
                        <Text numberOfLines={1} style={styles.headerTitle}>
                            {selectedTerminal?.title || (paired ? 'Choose terminal' : 'GhoDex Remote')}
                        </Text>
                        <Text numberOfLines={1} style={styles.headerSubtitle}>
                            {selectedTerminal?.workingDirectory || syncLabel}
                        </Text>
                    </View>
                </View>

                {errorMessage ? (
                    <View style={styles.errorBar}>
                        <Ionicons color="#a9412b" name="alert-circle-outline" size={16} />
                        <Text selectable style={styles.errorText}>{errorMessage}</Text>
                    </View>
                ) : null}

                <KeyboardAvoidingView
                    behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
                    style={styles.workspaceKeyboardFrame}
                >
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
                                            busy={busyAction === 'terminal-read' || busyAction === 'snapshot'}
                                            icon="sync-outline"
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
                            <View style={styles.commandRow}>
                                <TextInput
                                    autoCapitalize="none"
                                    autoCorrect={false}
                                    multiline
                                    onChangeText={setTerminalCommand}
                                    placeholder="Run one line, paste real multi-line blocks."
                                    placeholderTextColor="#8f867a"
                                    style={styles.commandInput}
                                    value={terminalCommand}
                                />
                                <View style={styles.commandActions}>
                                    <WorkspaceSubmitButton
                                        busy={busyAction === 'terminal-command' || busyAction === 'terminal-send-text'}
                                        label={shouldPasteRawInput(terminalCommand) ? 'Paste' : 'Run'}
                                        onPress={handleSubmitInput}
                                    />
                                </View>
                            </View>
                        </View>
                    ) : null}
                </KeyboardAvoidingView>
                {sidebarVisible ? (
                    <Animated.View pointerEvents="box-none" style={[styles.contentBackdropLayer, { opacity: backdropOpacity }]}>
                        <Pressable onPress={() => setSidebarVisible(false)} style={styles.sidebarBackdrop} />
                    </Animated.View>
                ) : null}
            </Animated.View>
        </View>
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

function WorkspaceSubmitButton(props: {
    busy?: boolean;
    label: string;
    onPress: () => void;
}) {
    return (
        <Pressable
            disabled={props.busy}
            onPress={props.onPress}
            style={({ pressed }) => [
                styles.submitButton,
                pressed ? styles.iconButtonPressed : null,
                props.busy ? styles.iconButtonDisabled : null,
            ]}
        >
            {props.busy ? <ActivityIndicator color="#fffaf3" size="small" /> : <Text style={styles.submitButtonText}>{props.label}</Text>}
        </Pressable>
    );
}

function WorkspaceMiniAction(props: {
    busy?: boolean;
    icon: keyof typeof Ionicons.glyphMap;
    onPress: () => void;
}) {
    return (
        <Pressable
            disabled={props.busy}
            onPress={props.onPress}
            style={({ pressed }) => [
                styles.miniAction,
                pressed ? styles.iconButtonPressed : null,
                props.busy ? styles.iconButtonDisabled : null,
            ]}
        >
            {props.busy ? <ActivityIndicator color="#d9b68f" size="small" /> : <Ionicons color="#d9b68f" name={props.icon} size={15} />}
        </Pressable>
    );
}

function SidebarQuickAction(props: {
    icon: keyof typeof Ionicons.glyphMap;
    label: string;
    onPress: () => void;
}) {
    return (
        <Pressable onPress={props.onPress} style={({ pressed }) => [styles.sidebarQuickAction, pressed ? styles.sidebarTerminalItemPressed : null]}>
            <Ionicons color="#fff4e7" name={props.icon} size={18} />
            <Text style={styles.sidebarQuickActionText}>{props.label}</Text>
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
        overflow: 'hidden',
    },
    mainShell: {
        flex: 1,
        backgroundColor: '#100d0b',
    },
    contentBackdropLayer: {
        ...StyleSheet.absoluteFillObject,
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
        paddingBottom: 6,
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
        marginTop: 8,
        paddingHorizontal: 12,
        paddingVertical: 8,
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
        paddingTop: 6,
        paddingBottom: 6,
    },
    workspaceKeyboardFrame: {
        flex: 1,
        minHeight: 0,
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
        borderRadius: 18,
        borderWidth: 1,
        borderColor: '#2e241d',
        backgroundColor: '#0c0907',
        overflow: 'hidden',
    },
    terminalToolbar: {
        flexDirection: 'row',
        alignItems: 'center',
        justifyContent: 'space-between',
        gap: 8,
        paddingHorizontal: 12,
        paddingVertical: 7,
        borderBottomWidth: 1,
        borderBottomColor: '#221b16',
        backgroundColor: '#16110f',
    },
    terminalToolbarPath: {
        flex: 1,
        color: '#b8a894',
        fontSize: 11,
        lineHeight: 15,
        fontFamily: 'monospace',
    },
    terminalToolbarActions: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: 6,
    },
    miniAction: {
        minWidth: 30,
        paddingHorizontal: 7,
        paddingVertical: 6,
        borderRadius: 10,
        alignItems: 'center',
        justifyContent: 'center',
        backgroundColor: '#251d18',
    },
    syncBadge: {
        borderRadius: 999,
        paddingHorizontal: 8,
        paddingVertical: 5,
        backgroundColor: '#251d18',
    },
    syncBadgeLive: {
        backgroundColor: '#173225',
    },
    syncBadgeText: {
        color: '#d8c6b2',
        fontSize: 10,
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
        paddingHorizontal: 12,
        paddingVertical: 10,
        color: '#f8efe3',
        fontSize: 13,
        lineHeight: 20,
        fontFamily: 'monospace',
    },
    commandDock: {
        paddingHorizontal: 12,
        paddingTop: 8,
        backgroundColor: '#171210',
        borderTopWidth: 1,
        borderTopColor: '#2a211b',
    },
    commandRow: {
        flexDirection: 'row',
        alignItems: 'stretch',
        gap: 8,
    },
    commandInput: {
        flex: 1,
        minHeight: 46,
        maxHeight: 92,
        borderRadius: 14,
        backgroundColor: '#221b16',
        borderWidth: 1,
        borderColor: '#342921',
        paddingHorizontal: 12,
        paddingVertical: 9,
        color: '#fff7ed',
        fontSize: 14,
        textAlignVertical: 'top',
        fontFamily: 'monospace',
    },
    commandActions: {
        width: 78,
        alignSelf: 'stretch',
    },
    submitButton: {
        flex: 1,
        minHeight: 46,
        borderRadius: 12,
        alignItems: 'center',
        justifyContent: 'center',
        backgroundColor: '#8a4b2a',
        paddingHorizontal: 12,
    },
    submitButtonText: {
        color: '#fffaf3',
        fontSize: 13,
        fontWeight: '700',
    },
    sidebarPanel: {
        position: 'absolute',
        top: 0,
        bottom: 0,
        left: 0,
        zIndex: 20,
        backgroundColor: '#191411',
        borderRightWidth: 1,
        borderRightColor: '#2d241d',
        paddingHorizontal: 14,
        gap: 14,
        shadowColor: '#000',
        shadowOffset: { width: 8, height: 0 },
        shadowOpacity: 0.22,
        shadowRadius: 18,
        elevation: 24,
    },
    sidebarBackdrop: {
        flex: 1,
        backgroundColor: 'rgba(0, 0, 0, 0.28)',
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
    sidebarTabCard: {
        borderRadius: 20,
        paddingHorizontal: 12,
        paddingVertical: 12,
        backgroundColor: '#241d18',
        gap: 10,
    },
    sidebarTabCardActive: {
        backgroundColor: '#31241c',
        borderWidth: 1,
        borderColor: '#8a4b2a',
    },
    sidebarTabHeader: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: 10,
    },
    sidebarTabInfo: {
        flex: 1,
        gap: 3,
    },
    sidebarTabTitle: {
        color: '#f8efe3',
        fontSize: 15,
        fontWeight: '800',
    },
    sidebarTabTitleActive: {
        color: '#fff6ec',
    },
    sidebarTabMeta: {
        color: '#b7a490',
        fontSize: 12,
        lineHeight: 17,
    },
    sidebarTabMetaActive: {
        color: '#f1cfb3',
    },
    sidebarTabCloseButton: {
        width: 30,
        height: 30,
        borderRadius: 10,
        alignItems: 'center',
        justifyContent: 'center',
        backgroundColor: '#1a1410',
    },
    sidebarTabTerminalList: {
        gap: 8,
    },
    sidebarTerminalItem: {
        borderRadius: 18,
        paddingHorizontal: 14,
        paddingVertical: 12,
        backgroundColor: '#1b1511',
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
    sidebarQuickRow: {
        flexDirection: 'row',
        gap: 10,
    },
    sidebarQuickAction: {
        flex: 1,
        flexDirection: 'row',
        alignItems: 'center',
        gap: 10,
        borderRadius: 16,
        backgroundColor: '#241d18',
        paddingHorizontal: 14,
        paddingVertical: 13,
        justifyContent: 'center',
    },
    sidebarQuickActionText: {
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
