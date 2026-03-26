import { describe, expect, it } from 'vitest';

import {
    getGhoDexObservabilitySnapshot,
    recordBootstrapCompleted,
    recordBootstrapFailed,
    recordBootstrapStarted,
    recordLaunchReady,
    recordLaunchStarted,
    recordReconnectRecovered,
    recordReconnectScheduled,
    recordScreenReady,
    recordScreenStarted,
    recordTerminalUpdate,
    resetGhoDexObservability,
} from './observability';

describe('ghodex observability', () => {
    it('records launch and bootstrap timing', () => {
        resetGhoDexObservability();

        recordLaunchStarted(100);
        recordBootstrapStarted(120);
        recordBootstrapCompleted(180);
        recordLaunchReady(240);

        expect(getGhoDexObservabilitySnapshot()).toMatchObject({
            launch: {
                launchDurationMs: 140,
                bootstrapDurationMs: 60,
                bootstrapFailureCount: 0,
            },
        });
    });

    it('tracks bootstrap failures without clearing the last successful timing', () => {
        resetGhoDexObservability();

        recordBootstrapStarted(10);
        recordBootstrapCompleted(25);
        recordBootstrapFailed(40);

        expect(getGhoDexObservabilitySnapshot().launch).toMatchObject({
            bootstrapDurationMs: 15,
            bootstrapFailureCount: 1,
        });
    });

    it('tracks screen open latency and terminal update latency', () => {
        resetGhoDexObservability();

        const workspaceStartedAt = recordScreenStarted('workspace', 1_000);
        recordScreenReady('workspace', workspaceStartedAt, 1_250);
        recordTerminalUpdate('live', 48, 1_300);

        expect(getGhoDexObservabilitySnapshot()).toMatchObject({
            screens: {
                workspace: {
                    openCount: 1,
                    lastOpenLatencyMs: 250,
                },
            },
            terminal: {
                updateCount: 1,
                lastUpdateLatencyMs: 48,
                lastUpdateSource: 'live',
            },
        });
    });

    it('tracks reconnect scheduling and recovery latency', () => {
        resetGhoDexObservability();

        const reconnectStartedAt = recordReconnectScheduled('subscription_drop', 800, 2_000);
        recordReconnectRecovered(reconnectStartedAt, 2_550);

        expect(getGhoDexObservabilitySnapshot().connectivity).toMatchObject({
            reconnectCount: 1,
            lastReconnectReason: 'subscription_drop',
            lastReconnectDelayMs: 800,
            lastReconnectLatencyMs: 550,
        });
    });
});
