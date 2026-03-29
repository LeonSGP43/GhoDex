import * as React from 'react';
import {
    ActivityIndicator,
    Alert,
    Animated,
    Easing,
    Modal,
    Platform,
    Pressable,
    ScrollView,
    Text,
    TextInput,
    type NativeSyntheticEvent,
    type TextInputKeyPressEventData,
    useWindowDimensions,
    View,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useRouter } from 'expo-router';
import { useFocusEffect, useIsFocused } from '@react-navigation/native';
import { KeyboardAvoidingView } from 'react-native-keyboard-controller';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { StyleSheet, useUnistyles } from 'react-native-unistyles';
import { getCurrentLanguage } from '@/text';
import {
    closeTab as closeGatewayTab,
    createTab as createGatewayTab,
    fetchSnapshot,
    readTerminal,
    renameTab as renameGatewayTab,
    runTerminalCommand,
    sendTerminalKey,
    sendTerminalText,
    subscribeToGatewayEvents,
} from '@/ghodex/gateway';
import { INITIAL_GATEWAY_SESSION } from '@/ghodex/sessionState';
import { loadStoredSession, type StoredSession } from '@/ghodex/storage';
import { useLocalSetting } from '@/sync/storage';
import { TerminalRenderer } from '@/ghodex/terminal/TerminalRenderer';
import { applyTerminalRowDelta, buildTerminalRows, type TerminalRenderRow } from '@/ghodex/terminal/model';
import {
    applyTerminalDelta,
    shouldFallbackToTerminalSnapshot,
    shouldRequestTerminalDelta,
} from '@/ghodex/terminalTransport';
import {
    applyRealtimeLocalEchoPayload,
    appendLatencySample,
    describeTerminalDebugText,
    deriveRealtimeInputDelta,
    normalizeCommandInput,
    resolveRealtimeMutationRetryDelayMs,
    resolveRealtimeKeyPayload,
    resolveTerminalSubmitMutation,
    shouldDeferRealtimeLiveRead,
    summarizeLatency,
    TERMINAL_CONTROL_KEYS,
    type TerminalControlKeySpec,
} from '@/ghodex/terminalInput';
import {
    recordReconnectRecovered,
    recordReconnectScheduled,
    recordScreenReady,
    recordScreenStarted,
    recordTerminalUpdate,
} from '@/ghodex/observability';
import { ActionButton, SurfaceCard } from '@/ghodex/ui';
import type {
    GatewayEnvelope,
    SnapshotResult,
    TabRow,
    TerminalMutationResult,
    TerminalReadResult,
    TerminalRow,
} from '@/ghodex/types';

type BusyAction =
    | 'snapshot'
    | 'tab-create'
    | 'tab-close'
    | 'tab-rename'
    | 'terminal-read'
    | 'terminal-command'
    | 'terminal-send-text'
    | null;

type RealtimeMutationOperation =
    | { kind: 'text'; text: string; retries: number }
    | { kind: 'key'; keySpec: TerminalControlKeySpec; retries: number };

type LoadTerminalViewFn = (
    terminal: TerminalRow,
    authToken: string,
    options?: {
        expectedGeneration?: number;
        mode?: 'snapshot' | 'delta';
        sinceFrameId?: string;
        readAfterWriteId?: string;
        metricsSource?: string;
    },
) => Promise<TerminalReadResult>;

type RefreshSnapshotFn = (
    authToken: string,
    preferredTerminalId: string | null,
    terminalMetricsSource?: string,
) => Promise<SnapshotResult>;

const WRITE_SETTLE_ATTEMPTS = 6;
const WRITE_SETTLE_INTERVAL_MS = 250;
const REALTIME_INPUT_FLUSH_MS = 12;
const REALTIME_INPUT_MAX_BATCH_SIZE = 48;
const REALTIME_MUTATION_INTERLEAVE_MS = 12;
const BACKSPACE_KEYPRESS_HINT_WINDOW_MS = 220;
const REALTIME_BACKSPACE_KEY_SPEC: TerminalControlKeySpec = {
    id: 'backspace',
    label: '⌫',
    payload: '\u007F',
    terminalKey: 'backspace',
};

function sleep(ms: number): Promise<void> {
    return new Promise((resolve) => {
        setTimeout(resolve, ms);
    });
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

function fallbackTabLabel(tab: TabRow, tabLabel: string): string {
    return tab.windowNumber > 0 ? `${tabLabel} ${tab.windowNumber}` : tabLabel;
}

function tabPrimaryLabel(tab: TabRow, preferredTerminal: TerminalRow | null, tabLabel: string): string {
    const tabTitle = tab.title?.trim();
    const terminalTitle = preferredTerminal?.title?.trim();

    if (tab.terminals.length > 1) {
        if (tabHasDistinctTitle(tab) && tabTitle) {
            return tabTitle;
        }
        return fallbackTabLabel(tab, tabLabel);
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
    return fallbackTabLabel(tab, tabLabel);
}

function tabSecondaryLabel(
    tab: TabRow,
    preferredTerminal: TerminalRow | null,
    primaryLabel: string,
    terminalsCountLabel: (count: number) => string,
): string | null {
    if (tab.terminals.length > 1) {
        return terminalsCountLabel(tab.terminals.length);
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
    return event !== 'terminal.input.sent' && event !== 'terminal.command.sent' && event !== 'terminal.key.sent';
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

function isRecoverableTabMutationError(error: unknown): boolean {
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

function isUnsupportedGatewayCommand(error: unknown): boolean {
    return !!(
        error
        && typeof error === 'object'
        && 'code' in error
        && (error as { code?: unknown }).code === 'unsupported_command'
    );
}

function isGatewayConcurrentSessionLimitError(error: unknown): boolean {
    const message = error instanceof Error ? error.message.toLowerCase() : '';
    const code = (
        error
        && typeof error === 'object'
        && 'code' in error
    )
        ? String((error as { code?: unknown }).code ?? '').toLowerCase()
        : '';
    return code === 'session_limit_exceeded'
        || message.includes('concurrent session limit')
        || message.includes('session_limit_exceeded');
}

function renameTabErrorMessage(error: unknown): string {
    if (isGatewayAuthError(error)) {
        return 'Desktop authorization expired. Re-open Device and bind the phone again.';
    }

    if (isUnsupportedGatewayCommand(error)) {
        return 'The paired desktop app does not support tab rename yet. Restart or update that desktop GhoDex build first.';
    }

    return error instanceof Error ? error.message : 'Unexpected gateway error';
}

function getWorkspaceCopy(language = getCurrentLanguage()) {
    if (language === 'zh-Hans') {
        return {
            syncLive: '实时连接',
            syncReconnecting: (ms: number) => `实时重连中，${ms}ms 回退`,
            syncPolling: (ms: number) => `${ms}ms 轮询`,
            sidebarSummary: (tabs: number, terminals: number) => `${tabs} 个标签，${terminals} 个终端`,
            terminalsCount: (count: number) => `${count} 个终端`,
            loadingWorkspace: '正在加载 GhoDex 工作区…',
            noTerminalText: '还没有抓取到终端文本，点击刷新后再试。',
            openSidebarHint: '打开左侧边栏并选择一个终端会话。',
            renamePlaceholder: '标签标题',
            noActivePairing: '尚未绑定设备',
            workspaceTabs: '工作区标签',
            noTabDataYet: '还没有标签数据',
            noTabDataBody: '先绑定这台手机，再重新打开侧边栏管理桌面标签和切换终端。',
            device: '设备',
            settings: '设置',
            chooseTerminal: '选择终端',
            remoteTitle: 'GhoDex Remote',
            pairDesktopFirst: '先绑定桌面端',
            pairDesktopBody: '首页只保留终端工作区。设备绑定与连接控制放在 Device，应用偏好放在 Settings。',
            openDevice: '打开设备',
            openSettings: '设置',
            selectTerminalFromSidebar: '从侧边栏选择一个终端',
            commandPlaceholder: '直接输入终端文本；单行会自动回车执行。',
            commandPlaceholderRealtime: '实时按键流：在这里直接输入，按键会立即发送到终端。',
            tabLabel: '标签',
            send: '发送',
            realtimeInputModeHint: '实时按键流模式已开启（点击终端直接输入，快捷键保留 Enter / Ctrl / 方向键）',
            realtimeInputTapHint: '点击终端画面即可直接输入',
            renameTab: '重命名标签',
            renameHint: '留空会恢复为桌面端自动管理的默认标题。',
            cancel: '取消',
            save: '保存',
            liveBadge: '实时',
            reconnectingBadge: '重连中',
            latencyUnknown: '延迟 --',
            latencyLabel: (ms: number) => `延迟 ${ms}ms`,
        };
    }

    return {
        syncLive: 'Live stream',
        syncReconnecting: (ms: number) => `Live reconnecting, ${ms}ms fallback`,
        syncPolling: (ms: number) => `${ms}ms polling`,
        sidebarSummary: (tabs: number, terminals: number) => `${tabs} tabs, ${terminals} terminals`,
        terminalsCount: (count: number) => `${count} terminals`,
        loadingWorkspace: 'Loading GhoDex workspace…',
        noTerminalText: 'No terminal text captured yet. Refresh the terminal to fetch the visible surface.',
        openSidebarHint: 'Open the left sidebar and choose a terminal session.',
        renamePlaceholder: 'Tab title',
        noActivePairing: 'No active pairing yet',
        workspaceTabs: 'Workspace Tabs',
        noTabDataYet: 'No tab data yet',
        noTabDataBody: 'Pair the phone first, then reopen the sidebar to manage desktop tabs and switch terminal sessions.',
        device: 'Device',
        settings: 'Settings',
        chooseTerminal: 'Choose terminal',
        remoteTitle: 'GhoDex Remote',
        pairDesktopFirst: 'Pair your desktop first',
        pairDesktopBody: 'The home screen stays focused on the terminal panel. Device pairing and connection controls live under Device, while app preferences stay in Settings.',
        openDevice: 'Open Device',
        openSettings: 'Settings',
        selectTerminalFromSidebar: 'Select a terminal from the sidebar',
        commandPlaceholder: 'Send terminal text directly; single line auto-sends Enter.',
        commandPlaceholderRealtime: 'Realtime key stream: type here to send keys immediately.',
        tabLabel: 'Tab',
        send: 'Send',
        realtimeInputModeHint: 'Realtime key stream mode is enabled (tap terminal to type; quick keys keep Enter/Ctrl/arrows)',
        realtimeInputTapHint: 'Tap terminal viewport to type directly',
        renameTab: 'Rename Tab',
        renameHint: 'Leave the field empty to restore the desktop-managed automatic title.',
        cancel: 'Cancel',
        save: 'Save',
        liveBadge: 'Live',
        reconnectingBadge: 'Reconnecting',
        latencyUnknown: 'RTT --',
        latencyLabel: (ms: number) => `RTT ${ms}ms`,
    };
}

export default function GhoDexWorkspaceScreen() {
    const { theme } = useUnistyles();
    const router = useRouter();
    const isFocused = useIsFocused();
    const terminalInputMode = useLocalSetting('mobileTerminalInputMode');
    const currentLanguage = getCurrentLanguage();
    const copy = React.useMemo(() => getWorkspaceCopy(currentLanguage), [currentLanguage]);
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
    const [terminalRows, setTerminalRows] = React.useState<TerminalRenderRow[]>([]);
    const [terminalCommand, setTerminalCommand] = React.useState('');
    const [realtimeInputDraft, setRealtimeInputDraft] = React.useState('');
    const [realtimeLocalEcho, setRealtimeLocalEcho] = React.useState('');
    const [latencySamples, setLatencySamples] = React.useState<number[]>([]);
    const [renameTabTarget, setRenameTabTarget] = React.useState<TabRow | null>(null);
    const [renameTabDraft, setRenameTabDraft] = React.useState('');
    const [renameTabError, setRenameTabError] = React.useState<string | null>(null);
    const isRealtimeInputMode = terminalInputMode === 'realtime';
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
        ? (subscriptionOpen ? copy.syncLive : copy.syncReconnecting(session.pollIntervalMs))
        : copy.syncPolling(session.pollIntervalMs);
    const latencySummary = React.useMemo(() => summarizeLatency(latencySamples), [latencySamples]);
    const latencyLabel = latencySummary.lastMs === null
        ? copy.latencyUnknown
        : copy.latencyLabel(latencySummary.lastMs);
    const displayedControlKeys = React.useMemo(
        () => (
            isRealtimeInputMode
                ? TERMINAL_CONTROL_KEYS.filter((key) => key.id !== 'backspace')
                : TERMINAL_CONTROL_KEYS
        ),
        [isRealtimeInputMode],
    );
    const terminalEmptyText = selectedTerminal
        ? (terminalContent || copy.noTerminalText)
        : copy.openSidebarHint;
    const renameTabPlaceholder = renameTabTarget
        ? tabPrimaryLabel(renameTabTarget, pickPreferredTerminalInTab(renameTabTarget), copy.tabLabel)
        : copy.renamePlaceholder;
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
    const sidebarVisibleRef = React.useRef(sidebarVisible);
    const terminalViewRef = React.useRef<TerminalReadResult | null>(terminalView);
    const subscriptionSequenceRef = React.useRef(0);
    const commandInputRef = React.useRef<TextInput | null>(null);
    const realtimeInputDraftRef = React.useRef('');
    const realtimeBackspaceFromKeyPressRef = React.useRef(0);
    const liveReadInFlightRef = React.useRef(false);
    const liveReadPendingRef = React.useRef(false);
    const snapshotRefreshTimerRef = React.useRef<ReturnType<typeof setTimeout> | null>(null);
    const realtimeInputFlushTimerRef = React.useRef<ReturnType<typeof setTimeout> | null>(null);
    const realtimeInputBufferRef = React.useRef('');
    const realtimeInputInFlightRef = React.useRef(false);
    const realtimeMutationQueueRef = React.useRef<RealtimeMutationOperation[]>([]);
    const realtimeResyncPendingRef = React.useRef(false);
    const realtimeLastBackspaceKeypressAtRef = React.useRef(0);
    const realtimeInputDebugSeqRef = React.useRef(0);
    const loadTerminalViewRef = React.useRef<LoadTerminalViewFn | null>(null);
    const refreshSnapshotRef = React.useRef<RefreshSnapshotFn | null>(null);
    const driveSelectedTerminalFromSubscriptionRef = React.useRef<(() => void) | null>(null);
    const reconnectStartedAtRef = React.useRef<number | null>(null);
    const isRealtimeInputModeRef = React.useRef(isRealtimeInputMode);

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
        sidebarVisibleRef.current = sidebarVisible;
    }, [sidebarVisible]);

    React.useEffect(() => {
        terminalViewRef.current = terminalView;
        subscriptionSequenceRef.current = Math.max(subscriptionSequenceRef.current, terminalView?.lastSequence ?? 0);
    }, [terminalView]);

    React.useEffect(() => {
        realtimeInputDraftRef.current = realtimeInputDraft;
    }, [realtimeInputDraft]);

    React.useEffect(() => {
        isRealtimeInputModeRef.current = isRealtimeInputMode;
    }, [isRealtimeInputMode]);

    React.useEffect(() => () => {
        if (realtimeInputFlushTimerRef.current) {
            clearTimeout(realtimeInputFlushTimerRef.current);
            realtimeInputFlushTimerRef.current = null;
        }
    }, []);

    React.useEffect(() => {
        Animated.timing(sidebarProgress, {
            toValue: sidebarVisible ? 1 : 0,
            duration: sidebarVisible ? 240 : 200,
            easing: sidebarVisible ? Easing.out(Easing.cubic) : Easing.inOut(Easing.quad),
            useNativeDriver: true,
        }).start();
    }, [sidebarProgress, sidebarVisible]);

    React.useEffect(() => {
        if (!isFocused) {
            setSidebarVisible(false);
        }
    }, [isFocused]);

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
                setErrorMessage('Gateway authorization expired for this desktop build. Re-open Device and bind the phone again.');
                return;
            }
            setErrorMessage(message);
        } finally {
            setBusyAction(null);
        }
    }, []);

    const recordGatewayLatency = React.useCallback((startedAt: number) => {
        const elapsed = Date.now() - startedAt;
        setLatencySamples((current) => appendLatencySample(current, elapsed, 24));
    }, []);

    const runMeasuredGatewayRequest = React.useCallback(async <T,>(request: () => Promise<T>): Promise<T> => {
        const startedAt = Date.now();
        try {
            return await request();
        } finally {
            recordGatewayLatency(startedAt);
        }
    }, [recordGatewayLatency]);

    const logRealtimeInputDiagnostic = React.useCallback((event: string, payload: Record<string, unknown>) => {
        let payloadJson = '';
        try {
            payloadJson = JSON.stringify(payload);
        } catch {
            payloadJson = '"[payload_unserializable]"';
        }
        realtimeInputDebugSeqRef.current += 1;
        const line = `[ghodex-input] #${realtimeInputDebugSeqRef.current} ${event} ${payloadJson}`;

        const nativeLogger = (globalThis as {
            nativeLoggingHook?: (message: string, level: number) => void;
        }).nativeLoggingHook;

        if (typeof nativeLogger === 'function') {
            // level=1 routes to warning-level native log output.
            nativeLogger(line, 1);
        }

        if (__DEV__) {
            console.warn(line);
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
        setTerminalRows((current) => {
            if (options?.mergeDelta && result.mode === 'delta' && result.contentKind === 'delta') {
                if (!result.hasChanges) {
                    return current;
                }

                const merged = applyTerminalRowDelta(current, result.changedRows);
                if (merged !== null) {
                    return merged;
                }
            }

            return buildTerminalRows(result.content);
        });
        if (isRealtimeInputModeRef.current && result.hasChanges) {
            setRealtimeLocalEcho('');
        }

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

    const applyRealtimeLocalEcho = React.useCallback((payload: string) => {
        if (!payload) {
            return;
        }
        setRealtimeLocalEcho((current) => applyRealtimeLocalEchoPayload(current, payload));
    }, []);

    const applyTerminalMutation = React.useCallback((mutation: TerminalMutationResult) => {
        subscriptionSequenceRef.current = Math.max(subscriptionSequenceRef.current, mutation.sequence);
        setTerminalView((current) => {
            if (!current || current.terminalId !== mutation.terminalId) {
                return current;
            }
            return {
                ...current,
                generation: Math.max(current.generation, mutation.generation),
                lastSequence: Math.max(current.lastSequence, mutation.sequence),
            };
        });
        setSnapshot((current) => {
            if (!current) {
                return current;
            }
            return {
                ...current,
                lastSequence: Math.max(current.lastSequence, mutation.sequence),
                tabs: current.tabs.map((tab) => ({
                    ...tab,
                    terminals: tab.terminals.map((item) => (
                        item.terminalId === mutation.terminalId
                            ? { ...item, generation: Math.max(item.generation, mutation.generation) }
                            : item
                    )),
                })),
                terminals: current.terminals.map((item) => (
                    item.terminalId === mutation.terminalId
                        ? { ...item, generation: Math.max(item.generation, mutation.generation) }
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
            metricsSource?: string;
        },
    ) => {
        const activeSession = sessionRef.current;
        const updateStartedAt = Date.now();
        const metricsSource = options?.metricsSource ?? (options?.mode === 'delta' ? 'live' : 'manual');
        const result = await runMeasuredGatewayRequest(() => readTerminal({
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
        }));

        const currentTerminalView = terminalViewRef.current;
        const expectsDelta = options?.mode === 'delta';
        const deltaNeedsSnapshotFallback = shouldFallbackToTerminalSnapshot({
            requestMode: expectsDelta ? 'delta' : 'snapshot',
            requestedSinceFrameId: options?.sinceFrameId,
            currentView: currentTerminalView,
            result,
        });

        if (deltaNeedsSnapshotFallback) {
            const snapshotResult = await runMeasuredGatewayRequest(() => readTerminal({
                host: activeSession.host,
                port: activeSession.port,
                authToken,
                terminalId: terminal.terminalId,
                expectedGeneration: options?.expectedGeneration ?? result.generation,
                mode: 'snapshot',
                maxChars: 24_000,
                maxLines: 300,
                readAfterWriteId: options?.readAfterWriteId,
            }));
            applyTerminalResult(snapshotResult);
            recordTerminalUpdate(metricsSource, Date.now() - updateStartedAt);
            return snapshotResult;
        }

        applyTerminalResult(result, { mergeDelta: expectsDelta });
        recordTerminalUpdate(metricsSource, Date.now() - updateStartedAt);
        return result;
    }, [applyTerminalResult, runMeasuredGatewayRequest]);

    React.useEffect(() => {
        loadTerminalViewRef.current = loadTerminalViewImpl;
    }, [loadTerminalViewImpl]);

    const refreshSnapshotImpl = React.useCallback(async (
        authToken: string,
        preferredTerminalId: string | null,
        terminalMetricsSource = 'manual',
    ) => {
        const activeSession = sessionRef.current;
        const result = await runMeasuredGatewayRequest(() => fetchSnapshot({
            host: activeSession.host,
            port: activeSession.port,
            authToken,
        }));
        setAuthorizationRequired(false);
        setSnapshot(result);

        const nextTerminal = pickPreferredTerminal(result.terminals, preferredTerminalId);
        setSelectedTerminalId(nextTerminal?.terminalId ?? null);
        if (nextTerminal) {
            await loadTerminalViewImpl(nextTerminal, authToken, { metricsSource: terminalMetricsSource });
        } else {
            setTerminalView(null);
            setTerminalContent('');
            setTerminalRows([]);
        }
        return result;
    }, [loadTerminalViewImpl, runMeasuredGatewayRequest]);

    React.useEffect(() => {
        refreshSnapshotRef.current = refreshSnapshotImpl;
    }, [refreshSnapshotImpl]);

    const settleTerminalAfterWrite = React.useCallback(async (
        terminal: TerminalRow,
        authToken: string,
        mutation: TerminalMutationResult,
    ) => {
        const currentView = terminalViewRef.current;
        let sinceFrameId = shouldRequestTerminalDelta(currentView, terminal.terminalId)
            ? currentView?.frameId ?? undefined
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
                metricsSource: 'write-settle',
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
            metricsSource: 'write-settle',
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
            if (!authToken || sidebarVisibleRef.current) {
                return;
            }
            void refreshSnapshotRef.current?.(authToken, selectedTerminalIdRef.current);
        }, reason === 'resync' ? 0 : 120);
    }, []);

    const drainRealtimeMutationQueue = React.useCallback(async () => {
        if (realtimeInputInFlightRef.current) {
            return;
        }
        if (liveReadInFlightRef.current) {
            setTimeout(() => {
                void drainRealtimeMutationQueue();
            }, REALTIME_MUTATION_INTERLEAVE_MS);
            return;
        }
        realtimeInputInFlightRef.current = true;
        let nextDrainDelayMs = REALTIME_MUTATION_INTERLEAVE_MS;
        try {
            const activeSession = sessionRef.current;
            const authToken = activeSession.authToken.trim();
            const currentTerminal = selectedTerminalRef.current;
            if (!authToken || !currentTerminal) {
                realtimeMutationQueueRef.current = [];
                return;
            }

            const operation = realtimeMutationQueueRef.current.shift();
            if (!operation) {
                return;
            }
            logRealtimeInputDiagnostic('queue.consume', {
                kind: operation.kind,
                retries: operation.retries,
                queueRemaining: realtimeMutationQueueRef.current.length,
            });

            try {
                let mutation: TerminalMutationResult;
                if (operation.kind === 'text') {
                    logRealtimeInputDiagnostic('queue.send_text', {
                        payload: describeTerminalDebugText(operation.text, 48),
                        terminalId: currentTerminal.terminalId,
                    });

                    mutation = await runMeasuredGatewayRequest(() => sendTerminalText({
                        host: activeSession.host,
                        port: activeSession.port,
                        authToken,
                        terminalId: currentTerminal.terminalId,
                        text: operation.text,
                    }));
                } else {
                    const terminalKey = operation.keySpec.terminalKey?.trim();
                    if (!terminalKey) {
                        logRealtimeInputDiagnostic('queue.send_key_fallback_text', {
                            keyId: operation.keySpec.id,
                            payload: describeTerminalDebugText(operation.keySpec.payload, 16),
                            terminalId: currentTerminal.terminalId,
                        });
                        mutation = await runMeasuredGatewayRequest(() => sendTerminalText({
                            host: activeSession.host,
                            port: activeSession.port,
                            authToken,
                            terminalId: currentTerminal.terminalId,
                            text: operation.keySpec.payload,
                        }));
                    } else {
                        logRealtimeInputDiagnostic('queue.send_key', {
                            keyId: operation.keySpec.id,
                            terminalKey,
                            terminalId: currentTerminal.terminalId,
                        });
                        try {
                            mutation = await runMeasuredGatewayRequest(() => sendTerminalKey({
                                host: activeSession.host,
                                port: activeSession.port,
                                authToken,
                                terminalId: currentTerminal.terminalId,
                                terminalKey,
                            }));
                        } catch (error) {
                            if (!isUnsupportedGatewayCommand(error)) {
                                throw error;
                            }
                            logRealtimeInputDiagnostic('queue.send_key_unsupported_fallback', {
                                keyId: operation.keySpec.id,
                                terminalKey,
                                payload: describeTerminalDebugText(operation.keySpec.payload, 16),
                            });
                            mutation = await runMeasuredGatewayRequest(() => sendTerminalText({
                                host: activeSession.host,
                                port: activeSession.port,
                                authToken,
                                terminalId: currentTerminal.terminalId,
                                text: operation.keySpec.payload,
                            }));
                        }
                    }
                }

                setAuthorizationRequired(false);
                applyTerminalMutation(mutation);
                realtimeResyncPendingRef.current = true;
            } catch (error) {
                if (isGatewayAuthError(error)) {
                    logRealtimeInputDiagnostic('queue.error.auth', {
                        message: error instanceof Error ? error.message : String(error ?? ''),
                    });
                    setAuthorizationRequired(true);
                    setSubscriptionOpen(false);
                    setErrorMessage('Gateway authorization expired for this desktop build. Re-open Device and bind the phone again.');
                    realtimeMutationQueueRef.current = [];
                    return;
                }

                if (isGatewayConcurrentSessionLimitError(error) && operation.retries < 6) {
                    logRealtimeInputDiagnostic('queue.error.concurrent_retry', {
                        kind: operation.kind,
                        retries: operation.retries,
                        message: error instanceof Error ? error.message : String(error ?? ''),
                    });
                    realtimeMutationQueueRef.current.unshift({
                        ...operation,
                        retries: operation.retries + 1,
                    });
                    nextDrainDelayMs = resolveRealtimeMutationRetryDelayMs(operation.retries);
                    return;
                }

                const message = error instanceof Error ? error.message : 'Unexpected gateway error';
                logRealtimeInputDiagnostic('queue.error.unexpected', {
                    kind: operation.kind,
                    retries: operation.retries,
                    message,
                });
                setErrorMessage(message);
                realtimeResyncPendingRef.current = true;
            }
        } finally {
            realtimeInputInFlightRef.current = false;
            if (realtimeMutationQueueRef.current.length > 0) {
                // Yield between queued writes so subscription-driven reads can
                // interleave and reduce perceived input-to-render latency.
                setTimeout(() => {
                    void drainRealtimeMutationQueue();
                }, nextDrainDelayMs);
                return;
            }
            if (realtimeResyncPendingRef.current) {
                realtimeResyncPendingRef.current = false;
                driveSelectedTerminalFromSubscriptionRef.current?.();
            }
        }
    }, [applyTerminalMutation, logRealtimeInputDiagnostic, runMeasuredGatewayRequest]);

    const enqueueRealtimeMutation = React.useCallback((operation: RealtimeMutationOperation) => {
        realtimeMutationQueueRef.current.push(operation);
        logRealtimeInputDiagnostic('queue.enqueue', {
            kind: operation.kind,
            retries: operation.retries,
            queueSize: realtimeMutationQueueRef.current.length,
        });
        void drainRealtimeMutationQueue();
    }, [drainRealtimeMutationQueue, logRealtimeInputDiagnostic]);

    const flushRealtimeInputBuffer = React.useCallback(() => {
        const payload = realtimeInputBufferRef.current;
        if (!payload) {
            return;
        }
        realtimeInputBufferRef.current = '';
        logRealtimeInputDiagnostic('buffer.flush', {
            payload: describeTerminalDebugText(payload, 48),
        });
        enqueueRealtimeMutation({
            kind: 'text',
            text: payload,
            retries: 0,
        });
    }, [enqueueRealtimeMutation, logRealtimeInputDiagnostic]);

    const enqueueRealtimeInputPayload = React.useCallback((payload: string) => {
        if (!payload) {
            return;
        }
        if (isRealtimeInputModeRef.current) {
            applyRealtimeLocalEcho(payload);
        }
        logRealtimeInputDiagnostic('buffer.enqueue_input', {
            payload: describeTerminalDebugText(payload, 32),
            bufferBefore: describeTerminalDebugText(realtimeInputBufferRef.current, 48),
        });
        realtimeInputBufferRef.current += payload;
        logRealtimeInputDiagnostic('buffer.enqueue_result', {
            bufferAfter: describeTerminalDebugText(realtimeInputBufferRef.current, 48),
            flushTimerActive: realtimeInputFlushTimerRef.current !== null,
        });

        const shouldImmediateFlush = payload.length <= 2;
        if (shouldImmediateFlush) {
            if (realtimeInputFlushTimerRef.current) {
                clearTimeout(realtimeInputFlushTimerRef.current);
                realtimeInputFlushTimerRef.current = null;
            }
            flushRealtimeInputBuffer();
            return;
        }

        if (realtimeInputBufferRef.current.length >= REALTIME_INPUT_MAX_BATCH_SIZE) {
            if (realtimeInputFlushTimerRef.current) {
                clearTimeout(realtimeInputFlushTimerRef.current);
                realtimeInputFlushTimerRef.current = null;
            }
            flushRealtimeInputBuffer();
            return;
        }

        if (realtimeInputFlushTimerRef.current) {
            return;
        }

        realtimeInputFlushTimerRef.current = setTimeout(() => {
            realtimeInputFlushTimerRef.current = null;
            flushRealtimeInputBuffer();
        }, REALTIME_INPUT_FLUSH_MS);
    }, [applyRealtimeLocalEcho, flushRealtimeInputBuffer, logRealtimeInputDiagnostic]);

    React.useEffect(() => {
        if (isRealtimeInputMode) {
            return;
        }
        if (realtimeInputFlushTimerRef.current) {
            clearTimeout(realtimeInputFlushTimerRef.current);
            realtimeInputFlushTimerRef.current = null;
        }
        realtimeInputBufferRef.current = '';
        realtimeMutationQueueRef.current = [];
        realtimeInputInFlightRef.current = false;
        realtimeResyncPendingRef.current = false;
        realtimeBackspaceFromKeyPressRef.current = 0;
        realtimeLastBackspaceKeypressAtRef.current = 0;
        realtimeInputDraftRef.current = '';
        setRealtimeLocalEcho('');
        setRealtimeInputDraft('');
    }, [isRealtimeInputMode]);

    React.useEffect(() => {
        if (!isRealtimeInputMode) {
            return;
        }
        realtimeInputBufferRef.current = '';
        realtimeMutationQueueRef.current = [];
        realtimeInputInFlightRef.current = false;
        realtimeResyncPendingRef.current = false;
        realtimeBackspaceFromKeyPressRef.current = 0;
        realtimeLastBackspaceKeypressAtRef.current = 0;
        realtimeInputDraftRef.current = '';
        setRealtimeLocalEcho('');
        setRealtimeInputDraft('');
    }, [isRealtimeInputMode, selectedTerminalId]);

    const driveSelectedTerminalFromSubscription = React.useCallback(() => {
        if (shouldDeferRealtimeLiveRead({
            isRealtimeInputMode,
            writeInFlight: realtimeInputInFlightRef.current,
            bufferedInputLength: realtimeInputBufferRef.current.length,
            flushTimerActive: realtimeInputFlushTimerRef.current !== null,
        })) {
            realtimeResyncPendingRef.current = true;
            return;
        }

        if (liveReadInFlightRef.current) {
            liveReadPendingRef.current = true;
            return;
        }

        const activeSession = sessionRef.current;
        const authToken = activeSession.authToken.trim();
        const currentTerminal = selectedTerminalRef.current;
        if (!authToken || !currentTerminal || sidebarVisibleRef.current) {
            return;
        }

        liveReadInFlightRef.current = true;
        void (async () => {
            try {
                do {
                    liveReadPendingRef.current = false;
                    const currentView = terminalViewRef.current;
                    const deltaEnabled = shouldRequestTerminalDelta(currentView, currentTerminal.terminalId);
                    await loadTerminalViewRef.current?.(currentTerminal, authToken, {
                        expectedGeneration: currentView?.terminalId === currentTerminal.terminalId
                            ? currentView.generation
                            : currentTerminal.generation,
                        mode: deltaEnabled ? 'delta' : 'snapshot',
                        sinceFrameId: deltaEnabled
                            ? currentView?.frameId ?? undefined
                            : undefined,
                        metricsSource: 'live',
                    });
                } while (liveReadPendingRef.current);
            } catch (error) {
                if (isGatewayAuthError(error)) {
                    setAuthorizationRequired(true);
                    setSubscriptionOpen(false);
                    setErrorMessage('Gateway authorization expired for this desktop build. Re-open Device and bind the phone again.');
                    return;
                }
                console.warn('Failed to live-refresh terminal', error);
                scheduleSnapshotRefresh('resync');
            } finally {
                liveReadInFlightRef.current = false;
            }
        })();
    }, [isRealtimeInputMode, scheduleSnapshotRefresh]);

    React.useEffect(() => {
        driveSelectedTerminalFromSubscriptionRef.current = driveSelectedTerminalFromSubscription;
    }, [driveSelectedTerminalFromSubscription]);

    const handleSubscriptionEnvelope = React.useCallback((envelope: GatewayEnvelope) => {
        const result = envelope.result;
        if (envelope.status === 'ok' && result && typeof result === 'object') {
            const lastSequence = typeof result.last_sequence === 'number' ? result.last_sequence : null;
            if (lastSequence !== null) {
                subscriptionSequenceRef.current = Math.max(subscriptionSequenceRef.current, lastSequence);
            }
            if (reconnectStartedAtRef.current !== null) {
                recordReconnectRecovered(reconnectStartedAtRef.current);
                reconnectStartedAtRef.current = null;
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
        const workspaceOpenedAt = recordScreenStarted('workspace');
        const stored = await loadStoredSession();
        sessionRef.current = stored;
        setSession(stored);
        setLoaded(true);

        const authToken = stored.authToken.trim();
        if (!authToken) {
            setSnapshot(null);
            setSelectedTerminalId(null);
            setTerminalView(null);
            setTerminalContent('');
            setTerminalRows([]);
            setSubscriptionOpen(false);
            setAuthorizationRequired(false);
            setErrorMessage(null);
            recordScreenReady('workspace', workspaceOpenedAt);
            return;
        }

        try {
            await refreshSnapshotImpl(authToken, selectedTerminalIdRef.current, 'workspace-open');
            setErrorMessage(null);
            recordScreenReady('workspace', workspaceOpenedAt);
        } catch (error) {
            if (isGatewayAuthError(error)) {
                setAuthorizationRequired(true);
                setSubscriptionOpen(false);
                setErrorMessage('Gateway authorization expired for this desktop build. Re-open Device and bind the phone again.');
                recordScreenReady('workspace', workspaceOpenedAt);
                return;
            }
            const message = error instanceof Error ? error.message : 'Failed to load gateway snapshot';
            setErrorMessage(message);
            recordScreenReady('workspace', workspaceOpenedAt);
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
            setErrorMessage('No auth token yet. Open Device and pair first.');
            return;
        }

        void runAction('snapshot', async () => {
            await refreshSnapshotImpl(authToken, selectedTerminalIdRef.current, 'manual');
        });
    }, [refreshSnapshotImpl, runAction, session.authToken]);

    const handleSelectTerminal = React.useCallback((terminal: TerminalRow) => {
        const authToken = session.authToken.trim();
        if (!authToken) {
            setErrorMessage('No auth token yet. Open Device and pair first.');
            return;
        }

        setSelectedTerminalId(terminal.terminalId);
        setTerminalContent('');
        setTerminalRows([]);
        void runAction('terminal-read', async () => {
            await loadTerminalViewImpl(terminal, authToken, { metricsSource: 'manual' });
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
            setErrorMessage('No auth token yet. Open Device and pair first.');
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

    const dismissRenameTab = React.useCallback(() => {
        setRenameTabTarget(null);
        setRenameTabDraft('');
        setRenameTabError(null);
    }, []);

    const handleOpenRenameTab = React.useCallback((tab: TabRow) => {
        setRenameTabTarget(tab);
        setRenameTabDraft(tab.title?.trim() ?? '');
        setRenameTabError(null);
    }, []);

    const handleSubmitRenameTab = React.useCallback(() => {
        const authToken = session.authToken.trim();
        if (!authToken || !renameTabTarget) {
            setErrorMessage('No auth token yet. Open Device and pair first.');
            return;
        }

        void runAction('tab-rename', async () => {
            setRenameTabError(null);
            try {
                await renameGatewayTab({
                    host: session.host,
                    port: session.port,
                    authToken,
                    tabId: renameTabTarget.tabId,
                    title: renameTabDraft,
                    expectedGeneration: renameTabTarget.generation,
                });
            } catch (error) {
                if (isRecoverableTabMutationError(error)) {
                    await refreshSnapshotImpl(authToken, selectedTerminalIdRef.current);
                    setErrorMessage('The tab changed on desktop before the phone finished renaming it. The phone view has been resynced.');
                    dismissRenameTab();
                    return;
                }
                setRenameTabError(renameTabErrorMessage(error));
                throw error;
            }

            await refreshSnapshotImpl(authToken, selectedTerminalIdRef.current);
            dismissRenameTab();
        });
    }, [
        dismissRenameTab,
        refreshSnapshotImpl,
        renameTabDraft,
        renameTabTarget,
        runAction,
        session.authToken,
        session.host,
        session.port,
    ]);

    const handleCloseTab = React.useCallback((tab: TabRow) => {
        const authToken = session.authToken.trim();
        if (!authToken) {
            setErrorMessage('No auth token yet. Open Device and pair first.');
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
                                if (isRecoverableTabMutationError(error)) {
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
                    ? { expectedGeneration: terminalView.generation, mode: 'snapshot', metricsSource: 'manual' }
                    : { metricsSource: 'manual' },
            );
        });
    }, [loadTerminalViewImpl, runAction, selectedTerminal, session.authToken, terminalView]);

    const handleSubmitInput = React.useCallback(() => {
        if (!selectedTerminal) {
            setErrorMessage('Select a terminal first.');
            return;
        }

        const rawInput = terminalCommand;
        const mutationIntent = resolveTerminalSubmitMutation(
            rawInput,
            isRealtimeInputMode ? 'realtime' : 'simple',
        );
        if (!mutationIntent) {
            setErrorMessage('Input is empty.');
            return;
        }

        void runAction('terminal-send-text', async () => {
            const expectedGeneration = terminalView?.terminalId === selectedTerminal.terminalId
                ? terminalView.generation
                : selectedTerminal.generation;
            let mutation: TerminalMutationResult;
            if (mutationIntent.kind === 'run-command') {
                mutation = await runMeasuredGatewayRequest(() => runTerminalCommand({
                    host: session.host,
                    port: session.port,
                    authToken: session.authToken,
                    terminalId: selectedTerminal.terminalId,
                    commandText: mutationIntent.commandText,
                    expectedGeneration,
                }));
            } else {
                try {
                    mutation = await runMeasuredGatewayRequest(() => sendTerminalText({
                        host: session.host,
                        port: session.port,
                        authToken: session.authToken,
                        terminalId: selectedTerminal.terminalId,
                        text: mutationIntent.text,
                        expectedGeneration,
                    }));
                } catch (error) {
                    if (!isUnsupportedGatewayCommand(error)) {
                        throw error;
                    }

                    const fallbackCommandText = normalizeCommandInput(rawInput).trim();
                    if (!fallbackCommandText || mutationIntent.text.includes('\n')) {
                        throw error;
                    }

                    mutation = await runMeasuredGatewayRequest(() => runTerminalCommand({
                        host: session.host,
                        port: session.port,
                        authToken: session.authToken,
                        terminalId: selectedTerminal.terminalId,
                        commandText: fallbackCommandText,
                        expectedGeneration,
                    }));
                }
            }
            if (!isRealtimeInputMode) {
                setTerminalCommand('');
            }
            await settleTerminalAfterWrite(selectedTerminal, session.authToken, mutation);
        });
    }, [
        isRealtimeInputMode,
        runAction,
        runMeasuredGatewayRequest,
        selectedTerminal,
        session.authToken,
        session.host,
        session.port,
        settleTerminalAfterWrite,
        terminalCommand,
        terminalView,
    ]);

    const sendControlKeyMutation = React.useCallback(async (
        keySpec: TerminalControlKeySpec,
        terminal: TerminalRow,
        expectedGeneration: number,
    ): Promise<TerminalMutationResult> => {
        const terminalKey = keySpec.terminalKey;
        if (terminalKey) {
            try {
                return await runMeasuredGatewayRequest(() => sendTerminalKey({
                    host: session.host,
                    port: session.port,
                    authToken: session.authToken,
                    terminalId: terminal.terminalId,
                    terminalKey,
                    expectedGeneration,
                }));
            } catch (error) {
                if (!isUnsupportedGatewayCommand(error)) {
                    throw error;
                }
            }
        }

        return runMeasuredGatewayRequest(() => sendTerminalText({
            host: session.host,
            port: session.port,
            authToken: session.authToken,
            terminalId: terminal.terminalId,
            text: keySpec.payload,
            expectedGeneration,
        }));
    }, [
        runMeasuredGatewayRequest,
        session.authToken,
        session.host,
        session.port,
    ]);

    const handleSendControlKey = React.useCallback((keySpec: TerminalControlKeySpec) => {
        if (!selectedTerminal) {
            setErrorMessage('Select a terminal first.');
            return;
        }

        if (isRealtimeInputMode) {
            if (keySpec.terminalKey) {
                if (keySpec.id === 'enter' || keySpec.id === 'tab') {
                    applyRealtimeLocalEcho(keySpec.payload);
                }
                enqueueRealtimeMutation({
                    kind: 'key',
                    keySpec,
                    retries: 0,
                });
                return;
            }
            enqueueRealtimeInputPayload(keySpec.payload);
            return;
        }

        void runAction('terminal-send-text', async () => {
            const expectedGeneration = terminalView?.terminalId === selectedTerminal.terminalId
                ? terminalView.generation
                : selectedTerminal.generation;
            const mutation = await sendControlKeyMutation(
                keySpec,
                selectedTerminal,
                expectedGeneration,
            );
            await settleTerminalAfterWrite(selectedTerminal, session.authToken, mutation);
        });
    }, [
        enqueueRealtimeMutation,
        runAction,
        applyRealtimeLocalEcho,
        enqueueRealtimeInputPayload,
        isRealtimeInputMode,
        sendControlKeyMutation,
        selectedTerminal,
        session.authToken,
        settleTerminalAfterWrite,
        terminalView,
    ]);

    const handleCommandInputChange = React.useCallback((nextValue: string) => {
        if (!isRealtimeInputMode) {
            setTerminalCommand(nextValue);
            return;
        }

        const previousDraft = realtimeInputDraftRef.current;
        const pendingBackspaces = realtimeBackspaceFromKeyPressRef.current;
        const backspaceKeypressHint = Date.now() - realtimeLastBackspaceKeypressAtRef.current
            <= BACKSPACE_KEYPRESS_HINT_WINDOW_MS;
        logRealtimeInputDiagnostic('input.change.received', {
            previousDraft: describeTerminalDebugText(previousDraft, 32),
            nextDraft: describeTerminalDebugText(nextValue, 32),
            pendingBackspaces,
            backspaceKeypressHint,
        });

        const delta = deriveRealtimeInputDelta({
            previousDraft,
            nextDraft: nextValue,
            keypressBackspacesPending: pendingBackspaces,
            backspaceKeypressHint,
        });
        logRealtimeInputDiagnostic('input.change.delta', {
            emittedText: describeTerminalDebugText(delta.emittedText, 32),
            nextDraft: describeTerminalDebugText(delta.nextDraft, 32),
            remainingKeypressBackspaces: delta.remainingKeypressBackspaces,
        });
        realtimeBackspaceFromKeyPressRef.current = delta.remainingKeypressBackspaces;
        realtimeInputDraftRef.current = delta.nextDraft;
        setRealtimeInputDraft(delta.nextDraft);
        if (delta.emittedText) {
            enqueueRealtimeInputPayload(delta.emittedText);
        }
    }, [enqueueRealtimeInputPayload, isRealtimeInputMode, logRealtimeInputDiagnostic]);

    const handleRealtimeKeyPress = React.useCallback((event: NativeSyntheticEvent<TextInputKeyPressEventData>) => {
        if (!isRealtimeInputMode) {
            return;
        }

        const key = event.nativeEvent.key;
        const normalizedKey = typeof key === 'string' ? key.trim().toLowerCase() : '';
        logRealtimeInputDiagnostic('input.keypress.received', {
            key,
            normalizedKey,
            draft: describeTerminalDebugText(realtimeInputDraftRef.current, 32),
            pendingBackspaces: realtimeBackspaceFromKeyPressRef.current,
        });
        if (normalizedKey === 'backspace' || normalizedKey === 'delete' || normalizedKey === 'del') {
            realtimeLastBackspaceKeypressAtRef.current = Date.now();
            if (realtimeInputDraftRef.current.length > 0) {
                realtimeBackspaceFromKeyPressRef.current += 1;
            }
            logRealtimeInputDiagnostic('input.keypress.backspace', {
                draftLength: realtimeInputDraftRef.current.length,
                pendingBackspaces: realtimeBackspaceFromKeyPressRef.current,
            });
            applyRealtimeLocalEcho('\u007F');
            enqueueRealtimeMutation({
                kind: 'key',
                keySpec: REALTIME_BACKSPACE_KEY_SPEC,
                retries: 0,
            });
            return;
        }
        if (normalizedKey === 'enter' || normalizedKey === 'tab') {
            const payload = resolveRealtimeKeyPayload(
                normalizedKey === 'enter' ? 'Enter' : 'Tab',
            );
            if (payload) {
                logRealtimeInputDiagnostic('input.keypress.special', {
                    normalizedKey,
                    payload: describeTerminalDebugText(payload, 16),
                });
                enqueueRealtimeInputPayload(payload);
            }
        }
    }, [applyRealtimeLocalEcho, enqueueRealtimeInputPayload, enqueueRealtimeMutation, isRealtimeInputMode, logRealtimeInputDiagnostic]);

    const focusRealtimeTerminalInput = React.useCallback(() => {
        if (!isRealtimeInputMode || !selectedTerminal) {
            return;
        }
        commandInputRef.current?.focus();
    }, [isRealtimeInputMode, selectedTerminal]);

    React.useEffect(() => {
        const authToken = session.authToken.trim();
        if (!isFocused || !loaded || !authToken || !session.liveUpdatesEnabled || authorizationRequired || sidebarVisible) {
            setSubscriptionOpen(false);
            reconnectStartedAtRef.current = null;
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
                            reconnectStartedAtRef.current = null;
                            setErrorMessage('Gateway authorization expired for this desktop build. Re-open Device and bind the phone again.');
                            return;
                        }
                        console.warn('Gateway subscription dropped', error);
                        setSubscriptionOpen(false);
                        const delayMs = Math.max(500, session.pollIntervalMs * 4);
                        reconnectStartedAtRef.current = recordReconnectScheduled('subscription_drop', delayMs);
                        reconnectTimer = setTimeout(openSubscription, delayMs);
                    },
                });
            } catch (error) {
                const message = error instanceof Error ? error.message : 'Failed to open gateway subscription';
                console.warn(message);
                setSubscriptionOpen(false);
                const delayMs = Math.max(500, session.pollIntervalMs * 4);
                reconnectStartedAtRef.current = recordReconnectScheduled('subscription_open_failed', delayMs);
                reconnectTimer = setTimeout(openSubscription, delayMs);
            }
        };

        openSubscription();

        return () => {
            cancelled = true;
            setSubscriptionOpen(false);
            reconnectStartedAtRef.current = null;
            if (reconnectTimer) {
                clearTimeout(reconnectTimer);
            }
            unsubscribe?.();
        };
    }, [
        authorizationRequired,
        handleSubscriptionEnvelope,
        isFocused,
        loaded,
        session.authToken,
        session.host,
        session.liveUpdatesEnabled,
        session.pollIntervalMs,
        session.port,
        sidebarVisible,
    ]);

    React.useEffect(() => {
        const authToken = session.authToken.trim();
        if (!isFocused || !loaded || !authToken || !selectedTerminal || authorizationRequired || sidebarVisible) {
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
                const deltaEnabled = shouldRequestTerminalDelta(terminalView, selectedTerminal.terminalId);
                await loadTerminalViewImpl(selectedTerminal, authToken, {
                    expectedGeneration: terminalView?.terminalId === selectedTerminal.terminalId
                        ? terminalView.generation
                        : selectedTerminal.generation,
                    mode: deltaEnabled ? 'delta' : 'snapshot',
                    sinceFrameId: deltaEnabled
                        ? terminalView?.frameId ?? undefined
                        : undefined,
                    metricsSource: 'poll',
                });
            } catch (error) {
                if (isGatewayAuthError(error)) {
                    setAuthorizationRequired(true);
                    setSubscriptionOpen(false);
                    setErrorMessage('Gateway authorization expired for this desktop build. Re-open Device and bind the phone again.');
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
    }, [
        authorizationRequired,
        busyAction,
        isFocused,
        loadTerminalViewImpl,
        loaded,
        selectedTerminal,
        session.authToken,
        session.liveUpdatesEnabled,
        session.pollIntervalMs,
        sidebarVisible,
        subscriptionOpen,
        terminalView,
    ]);

    const openDevice = React.useCallback(() => {
        router.push('/gateway');
    }, [router]);

    const openSettings = React.useCallback(() => {
        router.push('/settings');
    }, [router]);

    if (!loaded) {
        return (
            <View style={styles.loadingScreen}>
                <ActivityIndicator size="large" color={theme.colors.button.primary.background} />
                <Text style={styles.loadingText}>{copy.loadingWorkspace}</Text>
            </View>
        );
    }

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
                            {paired ? copy.sidebarSummary(tabCount, terminalCount) : copy.noActivePairing}
                        </Text>
                    </View>
                    <WorkspaceIconButton
                        disabled={busyAction === 'tab-create'}
                        icon="add-outline"
                        onPress={handleCreateTab}
                    />
                </View>

                <Text style={styles.sidebarSectionTitle}>{copy.workspaceTabs}</Text>
                <ScrollView contentContainerStyle={styles.sidebarList} showsVerticalScrollIndicator={false} style={styles.sidebarScroll}>
                    {paired && snapshot?.tabs.length ? snapshot.tabs.map((tab) => {
                        const preferredTerminal = pickPreferredTerminalInTab(tab);
                        const tabActive = tab.tabId === selectedTab?.tabId;
                        const showTerminalList = tab.terminals.length > 1;
                        const primaryLabel = tabPrimaryLabel(tab, preferredTerminal, copy.tabLabel);
                        const secondaryLabel = tabSecondaryLabel(tab, preferredTerminal, primaryLabel, copy.terminalsCount);

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
                                        <View style={styles.sidebarTabTitleRow}>
                                            <Text numberOfLines={1} style={[
                                                styles.sidebarTabTitle,
                                                tabActive ? styles.sidebarTabTitleActive : null,
                                            ]}>
                                                {primaryLabel}
                                            </Text>
                                            {tab.hasBell ? <View style={styles.sidebarTabBellDot} /> : null}
                                        </View>
                                        {secondaryLabel ? (
                                            <Text numberOfLines={1} style={[
                                                styles.sidebarTabMeta,
                                                tabActive ? styles.sidebarTabMetaActive : null,
                                            ]}>
                                                {secondaryLabel}
                                            </Text>
                                        ) : null}
                                    </Pressable>
                                    <View style={styles.sidebarTabHeaderActions}>
                                        <Pressable
                                            hitSlop={8}
                                            onPress={() => handleOpenRenameTab(tab)}
                                            style={({ pressed }) => [
                                                styles.sidebarTabIconButton,
                                                pressed ? styles.sidebarTerminalItemPressed : null,
                                            ]}
                                        >
                                            <Ionicons color={theme.colors.textSecondary} name="create-outline" size={16} />
                                        </Pressable>
                                        <Pressable
                                            hitSlop={8}
                                            onPress={() => handleCloseTab(tab)}
                                            style={({ pressed }) => [
                                                styles.sidebarTabIconButton,
                                                pressed ? styles.sidebarTerminalItemPressed : null,
                                            ]}
                                        >
                                            <Ionicons color={theme.colors.textSecondary} name="close-outline" size={18} />
                                        </Pressable>
                                    </View>
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
                            <Text style={styles.sidebarEmptyTitle}>{copy.noTabDataYet}</Text>
                            <Text style={styles.sidebarEmptyText}>
                                {copy.noTabDataBody}
                            </Text>
                        </View>
                    )}
                </ScrollView>

                <View style={styles.sidebarFooter}>
                    <View style={styles.sidebarQuickRow}>
                        <SidebarQuickAction icon="qr-code-outline" label={copy.device} onPress={openDevice} />
                        <SidebarQuickAction icon="settings-outline" label={copy.settings} onPress={openSettings} />
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
                            {selectedTerminal?.title || (paired ? copy.chooseTerminal : copy.remoteTitle)}
                        </Text>
                        <Text numberOfLines={1} style={styles.headerSubtitle}>
                            {selectedTerminal?.workingDirectory || syncLabel}
                        </Text>
                    </View>
                </View>

                {errorMessage ? (
                    <View style={styles.errorBar}>
                        <Ionicons color={theme.colors.box.error.text} name="alert-circle-outline" size={16} />
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
                                <SurfaceCard title={copy.pairDesktopFirst} subtitle={copy.pairDesktopBody}>
                                    <View style={styles.emptyActions}>
                                        <ActionButton label={copy.openDevice} onPress={openDevice} />
                                        <ActionButton kind="secondary" label={copy.openSettings} onPress={openSettings} />
                                    </View>
                                </SurfaceCard>
                            </View>
                        ) : (
                            <View style={styles.terminalShell}>
                                <View style={styles.terminalToolbar}>
                                    <Text numberOfLines={1} style={styles.terminalToolbarPath}>
                                        {selectedTerminal?.workingDirectory || copy.selectTerminalFromSidebar}
                                    </Text>
                                    <View style={styles.terminalToolbarActions}>
                                        <LatencyBadge active={latencySummary.lastMs !== null} label={latencyLabel} />
                                        <SyncBadge
                                            live={session.liveUpdatesEnabled}
                                            liveLabel={copy.liveBadge}
                                            open={subscriptionOpen}
                                            pollIntervalMs={session.pollIntervalMs}
                                            reconnectingLabel={copy.reconnectingBadge}
                                        />
                                        <WorkspaceMiniAction
                                            busy={busyAction === 'terminal-read' || busyAction === 'snapshot'}
                                            icon="sync-outline"
                                            onPress={handleRefreshTerminal}
                                        />
                                    </View>
                                </View>

                                <View
                                    onTouchEnd={isRealtimeInputMode ? focusRealtimeTerminalInput : undefined}
                                    style={styles.terminalViewport}
                                >
                                    {terminalRows.length > 0 ? (
                                        <TerminalRenderer
                                            optimisticInput={isRealtimeInputMode ? realtimeLocalEcho : ''}
                                            rows={terminalRows}
                                        />
                                    ) : (
                                        <ScrollView nestedScrollEnabled style={styles.terminalScroll}>
                                            <Text selectable style={styles.terminalContent}>
                                                {terminalEmptyText}
                                            </Text>
                                        </ScrollView>
                                    )}
                                </View>
                                {isRealtimeInputMode ? (
                                    <TextInput
                                        autoCapitalize="none"
                                        autoComplete="off"
                                        autoCorrect={false}
                                        blurOnSubmit={false}
                                        contextMenuHidden
                                        multiline={false}
                                        spellCheck={false}
                                        ref={commandInputRef}
                                        onChangeText={handleCommandInputChange}
                                        onKeyPress={handleRealtimeKeyPress}
                                        style={styles.realtimeInputCapture}
                                        value={realtimeInputDraft}
                                    />
                                ) : null}
                            </View>
                        )}
                    </View>

                    {paired ? (
                        <View style={[styles.commandDock, { paddingBottom: Math.max(insets.bottom, 12) }]}>
                            <ScrollView
                                horizontal
                                keyboardDismissMode="none"
                                keyboardShouldPersistTaps="always"
                                showsHorizontalScrollIndicator={false}
                                contentContainerStyle={styles.commandControlList}
                                style={styles.commandControlScroll}
                            >
                                {displayedControlKeys.map((key) => (
                                    <Pressable
                                        key={key.id}
                                        onPress={() => handleSendControlKey(key)}
                                        style={({ pressed }) => [
                                            styles.commandControlButton,
                                            pressed ? styles.iconButtonPressed : null,
                                        ]}
                                    >
                                        <Text style={styles.commandControlButtonText}>{key.label}</Text>
                                    </Pressable>
                                ))}
                            </ScrollView>
                            {isRealtimeInputMode ? (
                                <Text style={styles.commandModeHint}>
                                    {copy.realtimeInputModeHint} · {copy.realtimeInputTapHint}
                                </Text>
                            ) : null}
                            {!isRealtimeInputMode ? (
                                <View style={styles.commandRow}>
                                    <TextInput
                                        autoCapitalize="none"
                                        autoComplete="off"
                                        autoCorrect={false}
                                        blurOnSubmit={false}
                                        multiline
                                        spellCheck={false}
                                        ref={commandInputRef}
                                        onChangeText={handleCommandInputChange}
                                        placeholder={copy.commandPlaceholder}
                                        placeholderTextColor={theme.colors.input.placeholder}
                                        style={styles.commandInput}
                                        value={terminalCommand}
                                    />
                                    <View style={styles.commandActions}>
                                        <WorkspaceSubmitButton
                                            busy={busyAction === 'terminal-command' || busyAction === 'terminal-send-text'}
                                            label={copy.send}
                                            onPress={handleSubmitInput}
                                        />
                                    </View>
                                </View>
                            ) : null}
                        </View>
                    ) : null}
                </KeyboardAvoidingView>
                {sidebarVisible ? (
                    <Animated.View pointerEvents="box-none" style={[styles.contentBackdropLayer, { opacity: backdropOpacity }]}>
                        <Pressable onPress={() => setSidebarVisible(false)} style={styles.sidebarBackdrop} />
                    </Animated.View>
                ) : null}
            </Animated.View>
            <Modal
                animationType="fade"
                onRequestClose={dismissRenameTab}
                transparent
                visible={!!renameTabTarget}
            >
                <View style={styles.renameModalRoot}>
                    <Pressable onPress={dismissRenameTab} style={styles.renameModalBackdrop} />
                    <KeyboardAvoidingView
                        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
                        style={styles.renameModalKeyboard}
                    >
                        <View style={[styles.renameModalCard, { marginBottom: Math.max(insets.bottom, 16) }]}>
                            <Text style={styles.renameModalTitle}>{copy.renameTab}</Text>
                            <Text style={styles.renameModalSubtitle}>{copy.renameHint}</Text>
                            <TextInput
                                autoCapitalize="none"
                                autoCorrect={false}
                                autoFocus
                                onChangeText={(value) => {
                                    setRenameTabDraft(value);
                                    if (renameTabError) {
                                        setRenameTabError(null);
                                    }
                                }}
                                placeholder={renameTabPlaceholder}
                                placeholderTextColor={theme.colors.input.placeholder}
                                style={styles.renameModalInput}
                                value={renameTabDraft}
                            />
                            {renameTabError ? (
                                <Text style={styles.renameModalErrorText}>{renameTabError}</Text>
                            ) : null}
                            <View style={styles.renameModalActions}>
                                <ActionButton compact kind="secondary" label={copy.cancel} onPress={dismissRenameTab} />
                                <ActionButton
                                    busy={busyAction === 'tab-rename'}
                                    compact
                                    label={copy.save}
                                    onPress={handleSubmitRenameTab}
                                />
                            </View>
                        </View>
                    </KeyboardAvoidingView>
                </View>
            </Modal>
        </View>
    );
}

function WorkspaceIconButton(props: {
    disabled?: boolean;
    icon: keyof typeof Ionicons.glyphMap;
    onPress: () => void;
}) {
    const { theme } = useUnistyles();

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
            <Ionicons color={theme.colors.text} name={props.icon} size={22} />
        </Pressable>
    );
}

function WorkspaceSubmitButton(props: {
    busy?: boolean;
    label: string;
    onPress: () => void;
}) {
    const { theme } = useUnistyles();

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
            {props.busy ? <ActivityIndicator color={theme.colors.button.primary.tint} size="small" /> : <Text style={styles.submitButtonText}>{props.label}</Text>}
        </Pressable>
    );
}

function WorkspaceMiniAction(props: {
    busy?: boolean;
    icon: keyof typeof Ionicons.glyphMap;
    onPress: () => void;
}) {
    const { theme } = useUnistyles();

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
            {props.busy ? <ActivityIndicator color={theme.colors.textSecondary} size="small" /> : <Ionicons color={theme.colors.textSecondary} name={props.icon} size={15} />}
        </Pressable>
    );
}

function SidebarQuickAction(props: {
    icon: keyof typeof Ionicons.glyphMap;
    label: string;
    onPress: () => void;
}) {
    const { theme } = useUnistyles();

    return (
        <Pressable onPress={props.onPress} style={({ pressed }) => [styles.sidebarQuickAction, pressed ? styles.sidebarTerminalItemPressed : null]}>
            <Ionicons color={theme.colors.text} name={props.icon} size={18} />
            <Text style={styles.sidebarQuickActionText}>{props.label}</Text>
        </Pressable>
    );
}

function LatencyBadge(props: {
    active: boolean;
    label: string;
}) {
    return (
        <View style={[
            styles.latencyBadge,
            props.active ? styles.latencyBadgeLive : null,
        ]}>
            <Text style={styles.latencyBadgeText}>{props.label}</Text>
        </View>
    );
}

function SyncBadge(props: {
    live: boolean;
    liveLabel: string;
    open: boolean;
    pollIntervalMs: number;
    reconnectingLabel: string;
}) {
    const label = props.live
        ? (props.open ? props.liveLabel : props.reconnectingLabel)
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

const styles = StyleSheet.create((theme) => ({
    screen: {
        flex: 1,
        backgroundColor: theme.colors.groupped.background,
        overflow: 'hidden',
    },
    mainShell: {
        flex: 1,
        backgroundColor: theme.colors.groupped.background,
    },
    contentBackdropLayer: {
        ...StyleSheet.absoluteFillObject,
    },
    loadingScreen: {
        flex: 1,
        alignItems: 'center',
        justifyContent: 'center',
        gap: 12,
        backgroundColor: theme.colors.groupped.background,
    },
    loadingText: {
        color: theme.colors.textSecondary,
        fontSize: 16,
    },
    header: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: 12,
        paddingHorizontal: 16,
        paddingBottom: 6,
        backgroundColor: theme.colors.header.background,
        borderBottomWidth: 1,
        borderBottomColor: theme.colors.divider,
    },
    headerCopy: {
        flex: 1,
        gap: 2,
    },
    headerTitle: {
        color: theme.colors.text,
        fontSize: 17,
        fontWeight: '700',
    },
    headerSubtitle: {
        color: theme.colors.textSecondary,
        fontSize: 12,
        lineHeight: 17,
    },
    iconButton: {
        width: 40,
        height: 40,
        borderRadius: 14,
        alignItems: 'center',
        justifyContent: 'center',
        backgroundColor: theme.colors.surfaceHigh,
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
        borderColor: theme.colors.box.error.border,
        backgroundColor: theme.colors.box.error.background,
        flexDirection: 'row',
        alignItems: 'flex-start',
        gap: 8,
    },
    errorText: {
        flex: 1,
        color: theme.colors.box.error.text,
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
        borderColor: theme.colors.divider,
        backgroundColor: theme.colors.terminal.background,
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
        borderBottomColor: theme.colors.divider,
        backgroundColor: theme.colors.surface,
    },
    terminalToolbarPath: {
        flex: 1,
        color: theme.colors.textSecondary,
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
        backgroundColor: theme.colors.surfaceHigh,
    },
    syncBadge: {
        borderRadius: 999,
        paddingHorizontal: 8,
        paddingVertical: 5,
        backgroundColor: theme.colors.surfaceHigh,
    },
    syncBadgeLive: {
        backgroundColor: theme.colors.surfaceHighest,
    },
    syncBadgeText: {
        color: theme.colors.textSecondary,
        fontSize: 10,
        fontWeight: '700',
        textTransform: 'uppercase',
        letterSpacing: 0.5,
    },
    latencyBadge: {
        borderRadius: 999,
        paddingHorizontal: 8,
        paddingVertical: 5,
        backgroundColor: theme.colors.surfaceHigh,
        borderWidth: 1,
        borderColor: theme.colors.divider,
    },
    latencyBadgeLive: {
        borderColor: theme.colors.button.primary.background,
    },
    latencyBadgeText: {
        color: theme.colors.textSecondary,
        fontSize: 10,
        fontWeight: '700',
        letterSpacing: 0.2,
        fontFamily: 'monospace',
    },
    terminalViewport: {
        flex: 1,
        minHeight: 0,
    },
    realtimeInputCapture: {
        position: 'absolute',
        top: 0,
        left: 0,
        width: 1,
        height: 1,
        opacity: 0,
        padding: 0,
        margin: 0,
    },
    terminalScroll: {
        flex: 1,
    },
    terminalContent: {
        paddingHorizontal: 12,
        paddingVertical: 10,
        color: theme.colors.text,
        fontSize: 13,
        lineHeight: 20,
        fontFamily: 'monospace',
    },
    commandDock: {
        paddingHorizontal: 12,
        paddingTop: 8,
        backgroundColor: theme.colors.header.background,
        borderTopWidth: 1,
        borderTopColor: theme.colors.divider,
    },
    commandControlScroll: {
        marginBottom: 8,
    },
    commandControlList: {
        gap: 8,
        paddingRight: 6,
    },
    commandModeHint: {
        color: theme.colors.textSecondary,
        fontSize: 11,
        lineHeight: 16,
        marginBottom: 8,
        paddingHorizontal: 2,
    },
    commandControlButton: {
        minHeight: 34,
        paddingHorizontal: 11,
        borderRadius: 11,
        alignItems: 'center',
        justifyContent: 'center',
        backgroundColor: theme.colors.surfaceHigh,
        borderWidth: 1,
        borderColor: theme.colors.divider,
    },
    commandControlButtonText: {
        color: theme.colors.textSecondary,
        fontSize: 12,
        fontWeight: '700',
        fontFamily: 'monospace',
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
        backgroundColor: theme.colors.input.background,
        borderWidth: 1,
        borderColor: theme.colors.divider,
        paddingHorizontal: 12,
        paddingVertical: 9,
        color: theme.colors.input.text,
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
        backgroundColor: theme.colors.button.primary.background,
        paddingHorizontal: 12,
    },
    submitButtonText: {
        color: theme.colors.button.primary.tint,
        fontSize: 13,
        fontWeight: '700',
    },
    sidebarPanel: {
        position: 'absolute',
        top: 0,
        bottom: 0,
        left: 0,
        zIndex: 20,
        backgroundColor: theme.colors.surface,
        borderRightWidth: 1,
        borderRightColor: theme.colors.divider,
        paddingHorizontal: 14,
        gap: 14,
        shadowColor: theme.colors.shadow.color,
        shadowOffset: { width: 8, height: 0 },
        shadowOpacity: theme.colors.shadow.opacity,
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
        color: theme.colors.text,
        fontSize: 22,
        fontWeight: '800',
    },
    sidebarSubtitle: {
        color: theme.colors.textSecondary,
        fontSize: 13,
        lineHeight: 18,
    },
    sidebarSectionTitle: {
        color: theme.colors.groupped.sectionTitle,
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
        backgroundColor: theme.colors.surfaceHigh,
        gap: 10,
    },
    sidebarTabCardActive: {
        backgroundColor: theme.colors.surfaceHighest,
        borderWidth: 1,
        borderColor: theme.colors.button.primary.background,
    },
    sidebarTabHeader: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: 10,
    },
    sidebarTabHeaderActions: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: 8,
    },
    sidebarTabInfo: {
        flex: 1,
        gap: 3,
    },
    sidebarTabTitleRow: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: 8,
    },
    sidebarTabTitle: {
        flex: 1,
        color: theme.colors.text,
        fontSize: 15,
        fontWeight: '800',
    },
    sidebarTabTitleActive: {
        color: theme.colors.text,
    },
    sidebarTabBellDot: {
        width: 9,
        height: 9,
        borderRadius: 999,
        backgroundColor: theme.colors.status.connected,
    },
    sidebarTabMeta: {
        color: theme.colors.textSecondary,
        fontSize: 12,
        lineHeight: 17,
    },
    sidebarTabMetaActive: {
        color: theme.colors.text,
    },
    sidebarTabIconButton: {
        width: 30,
        height: 30,
        borderRadius: 10,
        alignItems: 'center',
        justifyContent: 'center',
        backgroundColor: theme.colors.surface,
    },
    sidebarTabTerminalList: {
        gap: 8,
    },
    sidebarTerminalItem: {
        borderRadius: 18,
        paddingHorizontal: 14,
        paddingVertical: 12,
        backgroundColor: theme.colors.surface,
        gap: 6,
    },
    sidebarTerminalItemActive: {
        backgroundColor: theme.colors.button.primary.background,
    },
    sidebarTerminalItemPressed: {
        opacity: 0.82,
    },
    sidebarTerminalTitle: {
        color: theme.colors.text,
        fontSize: 15,
        fontWeight: '700',
    },
    sidebarTerminalTitleActive: {
        color: theme.colors.button.primary.tint,
    },
    sidebarTerminalMeta: {
        color: theme.colors.textSecondary,
        fontSize: 12,
        lineHeight: 18,
        fontFamily: 'monospace',
    },
    sidebarTerminalMetaActive: {
        color: theme.colors.button.primary.tint,
    },
    sidebarEmpty: {
        borderRadius: 18,
        paddingHorizontal: 14,
        paddingVertical: 16,
        backgroundColor: theme.colors.surfaceHigh,
        gap: 8,
    },
    sidebarEmptyTitle: {
        color: theme.colors.text,
        fontSize: 15,
        fontWeight: '700',
    },
    sidebarEmptyText: {
        color: theme.colors.textSecondary,
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
        backgroundColor: theme.colors.surfaceHigh,
        paddingHorizontal: 14,
        paddingVertical: 13,
        justifyContent: 'center',
    },
    sidebarQuickActionText: {
        color: theme.colors.text,
        fontSize: 14,
        fontWeight: '700',
    },
    sidebarStatus: {
        borderRadius: 16,
        backgroundColor: theme.colors.surface,
        paddingHorizontal: 14,
        paddingVertical: 12,
        gap: 4,
    },
    sidebarStatusLine: {
        color: theme.colors.textSecondary,
        fontSize: 12,
        lineHeight: 17,
        fontFamily: 'monospace',
    },
    renameModalRoot: {
        flex: 1,
        backgroundColor: 'rgba(0, 0, 0, 0.42)',
        justifyContent: 'flex-end',
        paddingHorizontal: 16,
        paddingTop: 24,
    },
    renameModalBackdrop: {
        ...StyleSheet.absoluteFillObject,
    },
    renameModalKeyboard: {
        justifyContent: 'flex-end',
    },
    renameModalCard: {
        borderRadius: 22,
        backgroundColor: theme.colors.surface,
        borderWidth: 1,
        borderColor: theme.colors.divider,
        paddingHorizontal: 16,
        paddingTop: 18,
        paddingBottom: 16,
        gap: 12,
    },
    renameModalTitle: {
        color: theme.colors.text,
        fontSize: 18,
        fontWeight: '800',
    },
    renameModalSubtitle: {
        color: theme.colors.textSecondary,
        fontSize: 13,
        lineHeight: 19,
    },
    renameModalInput: {
        minHeight: 48,
        borderRadius: 14,
        backgroundColor: theme.colors.input.background,
        borderWidth: 1,
        borderColor: theme.colors.divider,
        paddingHorizontal: 12,
        paddingVertical: 10,
        color: theme.colors.input.text,
        fontSize: 15,
    },
    renameModalErrorText: {
        color: theme.colors.box.error.text,
        fontSize: 13,
        lineHeight: 18,
    },
    renameModalActions: {
        flexDirection: 'row',
        gap: 10,
    },
}));
