package com.leongong.ghodex.remote;

import java.util.ArrayList;
import java.util.List;

public final class GhoDexGatewayUiStore implements GhoDexGatewayClientStateMachine.StateListener {
    private volatile GhoDexGatewayUiSnapshot snapshot = new GhoDexGatewayUiSnapshot(
        null,
        false,
        null,
        null,
        false,
        false,
        List.of(),
        List.of(),
        List.of()
    );

    @Override
    public void onStateChanged(GhoDexGatewaySessionStore sessionStore, GhoDexTerminalIndexStore terminalIndexStore) {
        List<GhoDexGatewayUiSnapshot.TerminalRow> terminals = new ArrayList<>();
        for (GhoDexTerminalIndexStore.TerminalEntry terminal : terminalIndexStore.terminals()) {
            terminals.add(
                new GhoDexGatewayUiSnapshot.TerminalRow(
                    terminal.getTerminalId(),
                    terminal.getGeneration(),
                    terminal.getTitle(),
                    terminal.getWorkingDirectory(),
                    terminal.isFocused(),
                    terminal.isVisible(),
                    terminal.getLastEvent()
                )
            );
        }

        snapshot = new GhoDexGatewayUiSnapshot(
            sessionStore.getPairingCode(),
            sessionStore.getAuthToken() != null && !sessionStore.getAuthToken().isBlank(),
            sessionStore.getTokenId(),
            sessionStore.getProtocolVersion(),
            sessionStore.isSubscriptionOpen(),
            sessionStore.isSnapshotResyncRequired() || terminalIndexStore.isSnapshotResyncRequired(),
            sessionStore.getScopes(),
            new ArrayList<>(sessionStore.resumeState().observedTerminalIds()),
            terminals
        );
    }

    public GhoDexGatewayUiSnapshot snapshot() {
        return snapshot;
    }
}
