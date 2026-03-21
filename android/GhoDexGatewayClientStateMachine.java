import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.Objects;

public final class GhoDexGatewayClientStateMachine {
    public interface StateListener {
        void onStateChanged(GhoDexGatewaySessionStore sessionStore, GhoDexTerminalIndexStore terminalIndexStore);
    }

    private final GhoDexGatewayTransport transport;
    private final GhoDexGatewaySessionStore sessionStore;
    private final GhoDexTerminalIndexStore terminalIndexStore;
    private final CopyOnWriteArrayList<StateListener> stateListeners = new CopyOnWriteArrayList<>();
    private GhoDexGatewayTransport.Subscription subscription;

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
        String authToken = requireString(envelope, "auth_token");
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
        terminalIndexStore.resetForSnapshot();
        notifyStateChanged();
    }

    public void openSubscription(String requestId, int eventLimit) {
        closeSubscription();
        subscription = transport.openSubscription(
            sessionStore.resumeState().subscribeRequest(requestId, eventLimit),
            this::handleEnvelope
        );
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
        if (envelope.isOk() && "events.subscribe".equals(envelope.getRequestId())) {
            sessionStore.setSubscriptionOpen(true);
        }

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
}
