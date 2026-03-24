import * as React from 'react';
import {
    ActivityIndicator,
    Pressable,
    ScrollView,
    StyleSheet,
    Text,
    TextInput,
    useWindowDimensions,
    View,
} from 'react-native';
import { useRouter } from 'expo-router';
import { useFocusEffect } from '@react-navigation/native';
import {
    fetchSnapshot,
    readTerminal,
    runTerminalCommand,
    sendTerminalText,
} from '@/ghodex/gateway';
import { loadStoredSession, type StoredSession } from '@/ghodex/storage';
import { INITIAL_GATEWAY_SESSION } from '@/ghodex/sessionState';
import { ActionButton, InfoPill, SectionValue, SurfaceCard } from '@/ghodex/ui';
import type { SnapshotResult, TerminalChangedRow, TerminalReadResult, TerminalRow } from '@/ghodex/types';

type BusyAction =
    | 'snapshot'
    | 'terminal-read'
    | 'terminal-command'
    | 'terminal-send-text'
    | null;

const DELTA_POLL_INTERVAL_MS = 350;
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

export default function GhoDexWorkspaceScreen() {
    const router = useRouter();
    const { height, width } = useWindowDimensions();
    const [loaded, setLoaded] = React.useState(false);
    const [busyAction, setBusyAction] = React.useState<BusyAction>(null);
    const [errorMessage, setErrorMessage] = React.useState<string | null>(null);
    const [session, setSession] = React.useState<StoredSession>(INITIAL_GATEWAY_SESSION);
    const [snapshot, setSnapshot] = React.useState<SnapshotResult | null>(null);
    const [selectedTerminalId, setSelectedTerminalId] = React.useState<string | null>(null);
    const [terminalView, setTerminalView] = React.useState<TerminalReadResult | null>(null);
    const [terminalContent, setTerminalContent] = React.useState('');
    const [terminalCommand, setTerminalCommand] = React.useState('');
    const terminalPollInFlightRef = React.useRef(false);

    const isWideLayout = width >= 980;
    const terminalViewportHeight = Math.max(380, Math.min(isWideLayout ? height * 0.72 : height * 0.5, 700));

    const selectedTerminal = React.useMemo(
        () => snapshot?.terminals.find((terminal) => terminal.terminalId === selectedTerminalId) ?? null,
        [selectedTerminalId, snapshot],
    );

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
            return;
        }

        void runAction('snapshot', async () => {
            await refreshSnapshot(authToken, selectedTerminalId);
        });
    }, [refreshSnapshot, runAction, selectedTerminalId]);

    useFocusEffect(React.useCallback(() => {
        void hydrateSession();
        return undefined;
    }, [hydrateSession]));

    const handleRefreshSnapshot = React.useCallback(() => {
        const authToken = session.authToken.trim();
        if (!authToken) {
            setErrorMessage('No auth token yet. Open Pairing first.');
            return;
        }

        void runAction('snapshot', async () => {
            await refreshSnapshot(authToken, selectedTerminalId);
        });
    }, [refreshSnapshot, runAction, selectedTerminalId, session.authToken]);

    const handleSelectTerminal = React.useCallback((terminal: TerminalRow) => {
        const authToken = session.authToken.trim();
        if (!authToken) {
            setErrorMessage('No auth token yet. Open Pairing first.');
            return;
        }

        setSelectedTerminalId(terminal.terminalId);
        setTerminalContent('');
        void runAction('terminal-read', async () => {
            await loadTerminalView(terminal, authToken);
        });
    }, [loadTerminalView, runAction, session.authToken]);

    const handleRefreshTerminal = React.useCallback(() => {
        if (!selectedTerminal) {
            setErrorMessage('Select a terminal first.');
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
            setErrorMessage('Select a terminal first.');
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
            setErrorMessage('Select a terminal first.');
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
                <Text style={styles.loadingText}>Loading GhoDex workspace…</Text>
            </View>
        );
    }

    const paired = !!session.authToken.trim();

    return (
        <View style={styles.screen}>
            <View style={styles.heroCard}>
                <Text style={styles.eyebrow}>Workspace</Text>
                <Text style={styles.title}>Terminal-first mobile control</Text>
                <Text style={styles.subtitle}>
                    Pairing and gateway settings live in separate screens now. This page stays focused on the active terminal workspace.
                </Text>
                <View style={styles.heroPills}>
                    <InfoPill icon="radio-outline" label={`${session.host}:${session.port}`} />
                    <InfoPill icon="key-outline" label={paired ? 'Paired' : 'Unpaired'} />
                    <InfoPill icon="albums-outline" label={`${snapshot?.terminals.length ?? 0} terminals`} />
                </View>
                <View style={styles.topActions}>
                    <ActionButton kind="secondary" label="Open Pairing" onPress={() => router.push('/pairing')} />
                    <ActionButton kind="secondary" label="Gateway Settings" onPress={() => router.push('/gateway')} />
                </View>
            </View>

            {!paired ? (
                <View style={styles.emptyShell}>
                    <SurfaceCard
                        title="No active pairing yet"
                        subtitle="Use the Pairing screen to scan the desktop QR or exchange a pairing code. The workspace will stay here and refresh when you come back."
                    >
                        <View style={styles.emptyActions}>
                            <ActionButton label="Go To Pairing" onPress={() => router.push('/pairing')} />
                            <ActionButton kind="secondary" label="Gateway" onPress={() => router.push('/gateway')} />
                        </View>
                    </SurfaceCard>
                </View>
            ) : (
                <View style={styles.workspace}>
                    <View style={styles.workspaceHeader}>
                        <View style={styles.workspaceCopy}>
                            <Text style={styles.workspaceTitle}>{selectedTerminal?.title || 'Choose a terminal'}</Text>
                            <Text style={styles.workspaceSubtitle}>
                                {selectedTerminal?.workingDirectory || 'Pick an active desktop terminal from the strip below.'}
                            </Text>
                        </View>
                        <View style={styles.workspaceHeaderActions}>
                            <ActionButton busy={busyAction === 'snapshot'} kind="secondary" label="Refresh Snapshot" onPress={handleRefreshSnapshot} />
                        </View>
                    </View>

                    <ScrollView
                        horizontal
                        showsHorizontalScrollIndicator={false}
                        contentContainerStyle={styles.terminalStrip}
                        style={styles.terminalStripScroller}
                    >
                        {snapshot?.terminals.length ? snapshot.terminals.map((terminal) => (
                            <Pressable
                                key={terminal.terminalId}
                                onPress={() => handleSelectTerminal(terminal)}
                                style={({ pressed }) => [
                                    styles.terminalChip,
                                    terminal.terminalId === selectedTerminalId ? styles.terminalChipActive : null,
                                    pressed ? styles.chipPressed : null,
                                ]}
                            >
                                <Text style={[
                                    styles.terminalChipTitle,
                                    terminal.terminalId === selectedTerminalId ? styles.terminalChipTitleActive : null,
                                ]}>
                                    {terminal.title || terminal.terminalId.slice(0, 8)}
                                </Text>
                                <Text style={[
                                    styles.terminalChipMeta,
                                    terminal.terminalId === selectedTerminalId ? styles.terminalChipMetaActive : null,
                                ]} numberOfLines={1}>
                                    {terminal.workingDirectory || terminal.terminalId}
                                </Text>
                            </Pressable>
                        )) : (
                            <SurfaceCard title="No terminals yet" subtitle="Refresh the snapshot after the desktop test build is open.">
                                <ActionButton label="Refresh Snapshot" onPress={handleRefreshSnapshot} />
                            </SurfaceCard>
                        )}
                    </ScrollView>

                    <View style={[styles.terminalViewport, { minHeight: terminalViewportHeight }]}>
                        <ScrollView nestedScrollEnabled style={styles.terminalScroll}>
                            <Text selectable style={styles.terminalContent}>
                                {selectedTerminal
                                    ? (terminalContent || 'No terminal text captured yet. Refresh the terminal to fetch the visible surface.')
                                    : 'Select a terminal chip above to focus the workspace.'}
                            </Text>
                        </ScrollView>
                    </View>

                    <View style={styles.workspaceFooter}>
                        <View style={styles.workspaceFooterMeta}>
                            <SectionValue
                                label="Read"
                                mono
                                value={terminalView ? `${terminalView.consistency} / ${terminalView.returnedLines} lines` : 'not read yet'}
                            />
                        </View>
                        <View style={styles.workspaceFooterActions}>
                            <ActionButton busy={busyAction === 'terminal-read'} kind="secondary" label="Refresh Terminal" onPress={handleRefreshTerminal} />
                        </View>
                    </View>

                    {errorMessage ? (
                        <View style={styles.errorBox}>
                            <Text style={styles.errorTitle}>Gateway error</Text>
                            <Text style={styles.errorText}>{errorMessage}</Text>
                        </View>
                    ) : null}

                    <SurfaceCard title="Command Dock" subtitle="Like ChatGPT mobile input: this stays at the bottom while the workspace stays visible.">
                        <TextInput
                            autoCapitalize="none"
                            autoCorrect={false}
                            multiline
                            onChangeText={setTerminalCommand}
                            placeholder="Type shell input or a full command"
                            placeholderTextColor="#8f867a"
                            style={styles.commandInput}
                            value={terminalCommand}
                        />
                        <View style={styles.commandActions}>
                            <ActionButton busy={busyAction === 'terminal-send-text'} kind="secondary" label="Send Text" onPress={handleSendTerminalText} />
                            <ActionButton busy={busyAction === 'terminal-command'} label="Run Command" onPress={handleRunTerminalCommand} />
                        </View>
                    </SurfaceCard>
                </View>
            )}
        </View>
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
    heroPills: {
        flexDirection: 'row',
        flexWrap: 'wrap',
        gap: 8,
    },
    topActions: {
        flexDirection: 'row',
        gap: 12,
    },
    emptyShell: {
        flex: 1,
        justifyContent: 'center',
    },
    emptyActions: {
        flexDirection: 'row',
        gap: 12,
    },
    workspace: {
        flex: 1,
        gap: 14,
        minHeight: 0,
    },
    workspaceHeader: {
        flexDirection: 'row',
        alignItems: 'flex-start',
        justifyContent: 'space-between',
        gap: 12,
    },
    workspaceCopy: {
        flex: 1,
        gap: 6,
    },
    workspaceTitle: {
        color: '#241d17',
        fontSize: 22,
        fontWeight: '800',
    },
    workspaceSubtitle: {
        color: '#6b6259',
        fontSize: 13,
        lineHeight: 19,
    },
    workspaceHeaderActions: {
        width: 160,
    },
    terminalStripScroller: {
        flexGrow: 0,
    },
    terminalStrip: {
        gap: 10,
        paddingRight: 12,
    },
    terminalChip: {
        width: 230,
        borderRadius: 18,
        backgroundColor: '#efe4d8',
        paddingHorizontal: 14,
        paddingVertical: 12,
        gap: 4,
    },
    terminalChipActive: {
        backgroundColor: '#8a4b2a',
    },
    chipPressed: {
        opacity: 0.82,
    },
    terminalChipTitle: {
        color: '#3e3228',
        fontSize: 14,
        fontWeight: '700',
    },
    terminalChipTitleActive: {
        color: '#fff8ef',
    },
    terminalChipMeta: {
        color: '#65584d',
        fontSize: 12,
        fontFamily: 'monospace',
    },
    terminalChipMetaActive: {
        color: '#f2dfd0',
    },
    terminalViewport: {
        flex: 1,
        borderRadius: 22,
        borderWidth: 1,
        borderColor: '#d5c7b7',
        backgroundColor: '#17120f',
        overflow: 'hidden',
    },
    terminalScroll: {
        flex: 1,
    },
    terminalContent: {
        color: '#f7efe5',
        fontSize: 14,
        lineHeight: 22,
        fontFamily: 'monospace',
        padding: 16,
    },
    workspaceFooter: {
        flexDirection: 'row',
        alignItems: 'flex-end',
        gap: 12,
    },
    workspaceFooterMeta: {
        flex: 1,
    },
    workspaceFooterActions: {
        width: 170,
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
    commandInput: {
        backgroundColor: '#fffdf8',
        borderWidth: 1,
        borderColor: '#ded2c4',
        borderRadius: 14,
        paddingHorizontal: 14,
        paddingVertical: 12,
        color: '#2a221b',
        fontSize: 16,
        minHeight: 96,
        textAlignVertical: 'top',
        fontFamily: 'monospace',
    },
    commandActions: {
        flexDirection: 'row',
        gap: 12,
    },
});
