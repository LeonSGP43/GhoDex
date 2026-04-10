package com.leongong.ghodex.remote;

import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.Objects;

public final class GhoDexGatewayClientStateMachine {
    public interface StateListener {
        void onStateChanged(GhoDexGatewaySessionStore sessionStore, GhoDexTerminalIndexStore terminalIndexStore);
    }

    private final GhoDexGatewayTransport transport;
    private final GhoDexGatewaySessionStore sessionStore;
    private final GhoDexTerminalIndexStore terminalIndexStore;
    private final CopyOnWriteArrayList<StateListener> stateListeners = new CopyOnWriteArrayList<>();
    private BufferedEventStreamSubscription subscription;

    public GhoDexGatewayClientStateMachine(
        GhoDexGatewayTransport transport,
        GhoDexGatewaySessionStore sessionStore,
        GhoDexTerminalIndexStore terminalIndexStore
    ) {
        this.transport = Objects.requireNonNull(transport, "transport");
        this.sessionStore = Objects.requireNonNull(sessionStore, "sessionStore");
        this.terminalIndexStore = Objects.requireNonNull(terminalIndexStore, "terminalIndexStore");
    }

    public String beginPairing(String requestId, String client, List<String> requestedScopes) {
        GhoDexGatewayEnvelope envelope = transport.send(
            GhoDexGatewayRequest.pairingBegin(requestId, client, requestedScopes)
        );
        requireOk(envelope, "pairing begin");
        String pairingCode = requireString(envelope, "pairing_code");
        sessionStore.recordPairingCode(pairingCode);
        notifyStateChanged();
        return pairingCode;
    }

    public String exchangePairing(String requestId, String pairingCode) {
        GhoDexGatewayEnvelope envelope = transport.send(
            GhoDexGatewayRequest.pairingExchange(requestId, pairingCode)
        );
        requireOk(envelope, "pairing exchange");
        String authToken = firstRequiredString(envelope, "token", "auth_token");
        sessionStore.activateToken(
            authToken,
            requireString(envelope, "token_id"),
            envelope.resultStringList("scopes")
        );
        notifyStateChanged();
        return authToken;
    }

    public void refreshSnapshot(String requestId) {
        GhoDexGatewayEnvelope envelope = transport.send(
            sessionStore.resumeState().snapshotRequest(requestId)
        );
        requireOk(envelope, "snapshot");
        String protocolVersion = envelope.resultString("protocol_version");
        if (protocolVersion != null) {
            sessionStore.setProtocolVersion(protocolVersion);
        }
        sessionStore.clearSnapshotResyncRequirement();
        terminalIndexStore.applySnapshotEnvelope(envelope);
        notifyStateChanged();
    }

    public void openSubscription(String requestId, int eventLimit) {
        closeSubscription();
        GhoDexGatewayEnvelope envelope = transport.send(
            sessionStore.resumeState().subscribeRequest(requestId, eventLimit)
        );
        requireOk(envelope, "subscribe");
        subscription = new BufferedEventStreamSubscription(
            transport,
            sessionStore.getAuthToken(),
            requireString(envelope, "stream_id"),
            requestId,
            eventLimit,
            this::handleEnvelope
        );
        subscription.start();
        sessionStore.setSubscriptionOpen(true);
        notifyStateChanged();
    }

    public void observeTerminal(String terminalId) {
        sessionStore.resumeState().observeTerminal(terminalId);
        notifyStateChanged();
    }

    public GhoDexGatewayEnvelope readTerminalSnapshot(
        String requestId,
        String terminalId,
        String scope,
        int maxLines,
        int maxChars
    ) {
        GhoDexGatewayEnvelope envelope = transport.send(
            GhoDexGatewayRequest.readTerminalSnapshot(
                requestId,
                sessionStore.getAuthToken(),
                terminalId,
                scope,
                maxLines,
                maxChars
            )
        );
        requireOk(envelope, "read terminal");
        return envelope;
    }

    public GhoDexGatewayEnvelope sendText(String requestId, String terminalId, String text) {
        GhoDexGatewayEnvelope envelope = transport.send(
            GhoDexGatewayRequest.sendText(requestId, sessionStore.getAuthToken(), terminalId, text)
        );
        requireOk(envelope, "send text");
        return envelope;
    }

    public GhoDexGatewayEnvelope runCommand(String requestId, String terminalId, String commandText) {
        GhoDexGatewayEnvelope envelope = transport.send(
            GhoDexGatewayRequest.runCommand(requestId, sessionStore.getAuthToken(), terminalId, commandText)
        );
        requireOk(envelope, "run command");
        return envelope;
    }

    public void closeSubscription() {
        if (subscription != null) {
            subscription.close();
            subscription = null;
        }
        sessionStore.setSubscriptionOpen(false);
        notifyStateChanged();
    }

    public GhoDexGatewaySessionStore sessionStore() {
        return sessionStore;
    }

    public GhoDexTerminalIndexStore terminalIndexStore() {
        return terminalIndexStore;
    }

    public void addStateListener(StateListener listener) {
        stateListeners.add(Objects.requireNonNull(listener, "listener"));
        listener.onStateChanged(sessionStore, terminalIndexStore);
    }

    private void handleEnvelope(GhoDexGatewayEnvelope envelope) {
        if (envelope.isEvent()) {
            terminalIndexStore.applyEnvelope(envelope);
            sessionStore.resumeState().advanceSequence(envelope.getSequence());
            if (envelope.requiresSnapshotResync()) {
                sessionStore.requireSnapshotResync();
            }
        }
        notifyStateChanged();
    }

    private void notifyStateChanged() {
        for (StateListener listener : stateListeners) {
            listener.onStateChanged(sessionStore, terminalIndexStore);
        }
    }

    private static void requireOk(GhoDexGatewayEnvelope envelope, String operation) {
        if (!envelope.isOk()) {
            throw new IllegalStateException(
                operation + " failed: " + envelope.getErrorCode() + " " + envelope.getErrorMessage()
            );
        }
    }

    private static String requireString(GhoDexGatewayEnvelope envelope, String key) {
        String value = envelope.resultString(key);
        if (value == null || value.isBlank()) {
            throw new IllegalStateException("Missing " + key + " in " + envelope.getResult());
        }
        return value;
    }

    private static String firstRequiredString(
        GhoDexGatewayEnvelope envelope,
        String primaryKey,
        String fallbackKey
    ) {
        String primary = envelope.resultString(primaryKey);
        if (primary != null && !primary.isBlank()) {
            return primary;
        }
        return requireString(envelope, fallbackKey);
    }

    @FunctionalInterface
    private interface EventEnvelopeHandler {
        void onEnvelope(GhoDexGatewayEnvelope envelope);
    }

    private static final class BufferedEventStreamSubscription implements AutoCloseable {
        private static final long IDLE_POLL_BACKOFF_MS = 50L;

        private final GhoDexGatewayTransport transport;
        private final String authToken;
        private final String streamId;
        private final int eventLimit;
        private final String requestIdPrefix;
        private final EventEnvelopeHandler eventHandler;
        private final AtomicBoolean closed = new AtomicBoolean(false);
        private final Thread workerThread;
        private int drainRequestIndex;

        private BufferedEventStreamSubscription(
            GhoDexGatewayTransport transport,
            String authToken,
            String streamId,
            String requestIdPrefix,
            int eventLimit,
            EventEnvelopeHandler eventHandler
        ) {
            this.transport = transport;
            this.authToken = authToken;
            this.streamId = streamId;
            this.requestIdPrefix = requestIdPrefix;
            this.eventLimit = eventLimit;
            this.eventHandler = eventHandler;
            this.workerThread = new Thread(this::pollLoop, "ghodex-gateway-event-stream");
            this.workerThread.setDaemon(true);
        }

        private void start() {
            workerThread.start();
        }

        @Override
        public void close() {
            if (!closed.compareAndSet(false, true)) {
                return;
            }
            workerThread.interrupt();
            try {
                workerThread.join(200);
            } catch (InterruptedException interruptedException) {
                Thread.currentThread().interrupt();
            }
            try {
                transport.send(
                    GhoDexGatewayRequest.unsubscribeEvents(
                        requestIdPrefix + ".unsubscribe",
                        authToken,
                        streamId
                    )
                );
            } catch (RuntimeException ignored) {
                // Best-effort cleanup. The local state machine still closes the subscription.
            }
        }

        private void pollLoop() {
            try {
                while (!closed.get() && !Thread.currentThread().isInterrupted()) {
                    GhoDexGatewayEnvelope drainEnvelope = transport.send(
                        GhoDexGatewayRequest.drainEvents(
                            nextDrainRequestId(),
                            authToken,
                            streamId,
                            eventLimit
                        )
                    );
                    requireOk(drainEnvelope, "event drain");
                    List<java.util.Map<String, Object>> events = drainEnvelope.resultObjectList("events");
                    for (java.util.Map<String, Object> event : events) {
                        eventHandler.onEnvelope(GhoDexGatewayEnvelope.fromEventMap(event));
                    }
                    if (events.isEmpty()) {
                        Thread.sleep(IDLE_POLL_BACKOFF_MS);
                    }
                }
            } catch (InterruptedException interruptedException) {
                Thread.currentThread().interrupt();
            } catch (RuntimeException ignored) {
                // The polling loop is best-effort. A later reconnect or resubscribe can recover.
            }
        }

        private String nextDrainRequestId() {
            drainRequestIndex += 1;
            return requestIdPrefix + ".drain." + drainRequestIndex;
        }
    }
}
