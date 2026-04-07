type ScreenKey = 'device' | 'workspace';
type ReconnectReason =
    | 'subscription_drop'
    | 'subscription_open_failed'
    | 'terminal_stream_drop'
    | 'terminal_stream_open_failed';

type GhoDexObservabilitySnapshot = {
    launch: {
        launchStartedAtMs: number | null;
        launchReadyAtMs: number | null;
        launchDurationMs: number | null;
        bootstrapStartedAtMs: number | null;
        bootstrapCompletedAtMs: number | null;
        bootstrapDurationMs: number | null;
        bootstrapFailureCount: number;
    };
    screens: Record<ScreenKey, {
        openCount: number;
        lastOpenStartedAtMs: number | null;
        lastOpenReadyAtMs: number | null;
        lastOpenLatencyMs: number | null;
    }>;
    connectivity: {
        reconnectCount: number;
        lastReconnectReason: ReconnectReason | null;
        lastReconnectDelayMs: number | null;
        lastReconnectStartedAtMs: number | null;
        lastReconnectRecoveredAtMs: number | null;
        lastReconnectLatencyMs: number | null;
    };
    terminal: {
        updateCount: number;
        lastUpdateAtMs: number | null;
        lastUpdateLatencyMs: number | null;
        lastUpdateSource: string | null;
    };
};

function createInitialSnapshot(): GhoDexObservabilitySnapshot {
    return {
        launch: {
            launchStartedAtMs: null,
            launchReadyAtMs: null,
            launchDurationMs: null,
            bootstrapStartedAtMs: null,
            bootstrapCompletedAtMs: null,
            bootstrapDurationMs: null,
            bootstrapFailureCount: 0,
        },
        screens: {
            device: {
                openCount: 0,
                lastOpenStartedAtMs: null,
                lastOpenReadyAtMs: null,
                lastOpenLatencyMs: null,
            },
            workspace: {
                openCount: 0,
                lastOpenStartedAtMs: null,
                lastOpenReadyAtMs: null,
                lastOpenLatencyMs: null,
            },
        },
        connectivity: {
            reconnectCount: 0,
            lastReconnectReason: null,
            lastReconnectDelayMs: null,
            lastReconnectStartedAtMs: null,
            lastReconnectRecoveredAtMs: null,
            lastReconnectLatencyMs: null,
        },
        terminal: {
            updateCount: 0,
            lastUpdateAtMs: null,
            lastUpdateLatencyMs: null,
            lastUpdateSource: null,
        },
    };
}

let snapshot = createInitialSnapshot();

function emitObservation(event: string, payload: Record<string, unknown>) {
    if (typeof process !== 'undefined' && process.env.NODE_ENV === 'test') {
        return;
    }
    console.info(`[ghodex-observability] ${event}`, payload);
}

export function resetGhoDexObservability() {
    snapshot = createInitialSnapshot();
}

export function getGhoDexObservabilitySnapshot(): GhoDexObservabilitySnapshot {
    return {
        launch: { ...snapshot.launch },
        screens: {
            device: { ...snapshot.screens.device },
            workspace: { ...snapshot.screens.workspace },
        },
        connectivity: { ...snapshot.connectivity },
        terminal: { ...snapshot.terminal },
    };
}

export function recordLaunchStarted(now = Date.now()) {
    snapshot.launch.launchStartedAtMs = now;
}

export function recordLaunchReady(now = Date.now()) {
    snapshot.launch.launchReadyAtMs = now;
    snapshot.launch.launchDurationMs = snapshot.launch.launchStartedAtMs === null
        ? null
        : Math.max(0, now - snapshot.launch.launchStartedAtMs);
    emitObservation('launch.ready', {
        launchDurationMs: snapshot.launch.launchDurationMs,
    });
}

export function recordBootstrapStarted(now = Date.now()) {
    snapshot.launch.bootstrapStartedAtMs = now;
}

export function recordBootstrapCompleted(now = Date.now()) {
    snapshot.launch.bootstrapCompletedAtMs = now;
    snapshot.launch.bootstrapDurationMs = snapshot.launch.bootstrapStartedAtMs === null
        ? null
        : Math.max(0, now - snapshot.launch.bootstrapStartedAtMs);
}

export function recordBootstrapFailed(now = Date.now()) {
    snapshot.launch.bootstrapFailureCount += 1;
    if (
        snapshot.launch.bootstrapStartedAtMs !== null
        && snapshot.launch.bootstrapCompletedAtMs === null
    ) {
        snapshot.launch.bootstrapCompletedAtMs = now;
        snapshot.launch.bootstrapDurationMs = Math.max(0, now - snapshot.launch.bootstrapStartedAtMs);
    }
    emitObservation('bootstrap.failed', {
        bootstrapFailureCount: snapshot.launch.bootstrapFailureCount,
        bootstrapDurationMs: snapshot.launch.bootstrapDurationMs,
    });
}

export function recordScreenStarted(screen: ScreenKey, now = Date.now()): number {
    snapshot.screens[screen].lastOpenStartedAtMs = now;
    return now;
}

export function recordScreenReady(screen: ScreenKey, startedAt: number, now = Date.now()) {
    const screenMetrics = snapshot.screens[screen];
    screenMetrics.openCount += 1;
    screenMetrics.lastOpenReadyAtMs = now;
    screenMetrics.lastOpenLatencyMs = Math.max(0, now - startedAt);
}

export function recordReconnectScheduled(
    reason: ReconnectReason,
    delayMs: number,
    now = Date.now(),
): number {
    snapshot.connectivity.reconnectCount += 1;
    snapshot.connectivity.lastReconnectReason = reason;
    snapshot.connectivity.lastReconnectDelayMs = delayMs;
    snapshot.connectivity.lastReconnectStartedAtMs = now;
    emitObservation('reconnect.scheduled', {
        reason,
        delayMs,
        reconnectCount: snapshot.connectivity.reconnectCount,
    });
    return now;
}

export function recordReconnectRecovered(startedAt: number, now = Date.now()) {
    snapshot.connectivity.lastReconnectRecoveredAtMs = now;
    snapshot.connectivity.lastReconnectLatencyMs = Math.max(0, now - startedAt);
    emitObservation('reconnect.recovered', {
        latencyMs: snapshot.connectivity.lastReconnectLatencyMs,
    });
}

export function recordTerminalUpdate(source: string, latencyMs: number, now = Date.now()) {
    snapshot.terminal.updateCount += 1;
    snapshot.terminal.lastUpdateAtMs = now;
    snapshot.terminal.lastUpdateLatencyMs = Math.max(0, latencyMs);
    snapshot.terminal.lastUpdateSource = source;
}
