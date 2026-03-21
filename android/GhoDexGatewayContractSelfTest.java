import java.util.List;
import java.util.Map;

public final class GhoDexGatewayContractSelfTest {
    public static void main(String[] args) {
        pairingBeginSerializesScopes();
        subscribeUsesMonotonicResumeSequence();
        sendTextEscapesNewlines();
        readTerminalSnapshotCarriesWindowArgs();
        clientStateMachinePersistsPairingAndSnapshotState();
        subscriptionEventsUpdateTerminalIndexAndRequireResync();
        System.out.println("GhoDex gateway Android contract self-test passed");
    }

    private static void pairingBeginSerializesScopes() {
        String json = GhoDexGatewayRequest
            .pairingBegin("req-pair", "android-mvp", List.of("mutate", "observe"))
            .toJson();
        assertContains(json, "\"request_id\":\"req-pair\"");
        assertContains(json, "\"command\":\"gateway.pairing.begin\"");
        assertContains(json, "\"client\":\"android-mvp\"");
        assertContains(json, "\"requested_scopes\":[\"mutate\",\"observe\"]");
    }

    private static void subscribeUsesMonotonicResumeSequence() {
        GhoDexGatewayResumeState state = new GhoDexGatewayResumeState();
        state.setAuthToken("secret");
        state.advanceSequence(7);
        state.advanceSequence(3);
        state.advanceSequence(11);
        String json = state.subscribeRequest("req-subscribe", 32).toJson();
        assertContains(json, "\"auth_token\":\"secret\"");
        assertContains(json, "\"since_sequence\":11");
        assertContains(json, "\"event_limit\":32");
    }

    private static void sendTextEscapesNewlines() {
        String json = GhoDexGatewayRequest
            .sendText("req-send", "secret", "terminal-1", "echo hi\n")
            .toJson();
        assertContains(json, "\"command\":\"send-text\"");
        assertContains(json, "\"terminal_id\":\"terminal-1\"");
        assertContains(json, "\"text\":\"echo hi\\n\"");
    }

    private static void readTerminalSnapshotCarriesWindowArgs() {
        String json = GhoDexGatewayRequest
            .readTerminalSnapshot("req-read", "secret", "terminal-2", "visible", 80, 2000)
            .toJson();
        assertContains(json, "\"command\":\"read-terminal\"");
        assertContains(json, "\"scope\":\"visible\"");
        assertContains(json, "\"mode\":\"snapshot\"");
        assertContains(json, "\"max_lines\":80");
        assertContains(json, "\"max_chars\":2000");
    }

    private static void clientStateMachinePersistsPairingAndSnapshotState() {
        FakeTransport transport = new FakeTransport();
        GhoDexGatewaySessionStore sessionStore = new GhoDexGatewaySessionStore();
        GhoDexTerminalIndexStore terminalIndexStore = new GhoDexTerminalIndexStore();
        GhoDexGatewayClientStateMachine stateMachine = new GhoDexGatewayClientStateMachine(
            transport,
            sessionStore,
            terminalIndexStore
        );

        String pairingCode = stateMachine.beginPairing("req-pair-begin", "android-mvp", List.of("observe", "mutate"));
        assertEquals("PAIR-123", pairingCode);

        String authToken = stateMachine.exchangePairing("req-pair-exchange", pairingCode);
        assertEquals("token-live", authToken);
        assertEquals("token-live", sessionStore.getAuthToken());
        assertEquals("tok-1", sessionStore.getTokenId());
        assertEquals(List.of("observe", "mutate"), sessionStore.getScopes());

        stateMachine.refreshSnapshot("req-snapshot");
        assertEquals("1.0", sessionStore.getProtocolVersion());

        String sendJson = transport.lastRequestJson();
        assertContains(sendJson, "\"command\":\"snapshot\"");
        assertContains(sendJson, "\"auth_token\":\"token-live\"");
    }

    private static void subscriptionEventsUpdateTerminalIndexAndRequireResync() {
        FakeTransport transport = new FakeTransport();
        GhoDexGatewaySessionStore sessionStore = new GhoDexGatewaySessionStore();
        sessionStore.activateToken("token-live", "tok-1", List.of("observe"));
        GhoDexTerminalIndexStore terminalIndexStore = new GhoDexTerminalIndexStore();
        GhoDexGatewayClientStateMachine stateMachine = new GhoDexGatewayClientStateMachine(
            transport,
            sessionStore,
            terminalIndexStore
        );

        stateMachine.observeTerminal("terminal-1");
        stateMachine.openSubscription("events.subscribe", 32);

        transport.emitEvent(
            GhoDexGatewayEnvelope.event(
                7,
                "terminal.input.sent",
                "terminal",
                "terminal-1",
                3,
                Map.of("text_length", 4)
            )
        );

        GhoDexTerminalIndexStore.TerminalEntry terminal = terminalIndexStore.getTerminal("terminal-1");
        assertEquals("terminal.input.sent", terminal.getLastEvent());
        assertEquals(3, terminal.getGeneration());
        assertEquals(7L, terminalIndexStore.getLastSequence());
        assertEquals(7L, sessionStore.resumeState().getSinceSequence());

        transport.emitEvent(GhoDexGatewayEnvelope.overflow(8, 5));
        assertTrue(sessionStore.isSnapshotResyncRequired(), "overflow should require resync");
        assertTrue(terminalIndexStore.isSnapshotResyncRequired(), "index store should observe resync marker");

        stateMachine.closeSubscription();
        assertTrue(!sessionStore.isSubscriptionOpen(), "subscription should close cleanly");
    }

    private static void assertContains(String haystack, String needle) {
        if (!haystack.contains(needle)) {
            throw new AssertionError("Expected to find " + needle + " in " + haystack);
        }
    }

    private static void assertEquals(Object expected, Object actual) {
        if (!expected.equals(actual)) {
            throw new AssertionError("Expected " + expected + " but got " + actual);
        }
    }

    private static void assertTrue(boolean condition, String message) {
        if (!condition) {
            throw new AssertionError(message);
        }
    }

    private static final class FakeTransport implements GhoDexGatewayTransport {
        private EventSink sink;
        private String lastRequestJson = "";

        @Override
        public GhoDexGatewayEnvelope send(GhoDexGatewayRequest request) {
            lastRequestJson = request.toJson();
            return switch (request.command()) {
                case "gateway.pairing.begin" -> GhoDexGatewayEnvelope.ok(
                    request.requestId(),
                    Map.of("pairing_code", "PAIR-123")
                );
                case "gateway.pairing.exchange" -> GhoDexGatewayEnvelope.ok(
                    request.requestId(),
                    Map.of(
                        "auth_token", "token-live",
                        "token_id", "tok-1",
                        "scopes", List.of("observe", "mutate")
                    )
                );
                case "snapshot" -> GhoDexGatewayEnvelope.ok(
                    request.requestId(),
                    Map.of("protocol_version", "1.0")
                );
                case "send-text", "run-command", "read-terminal" -> GhoDexGatewayEnvelope.ok(
                    request.requestId(),
                    Map.of("accepted", Boolean.TRUE)
                );
                default -> GhoDexGatewayEnvelope.error(request.requestId(), "unsupported", request.command());
            };
        }

        @Override
        public Subscription openSubscription(GhoDexGatewayRequest request, EventSink sink) {
            this.lastRequestJson = request.toJson();
            this.sink = sink;
            sink.onEnvelope(
                GhoDexGatewayEnvelope.ok(
                    request.requestId(),
                    Map.of("live_stream_open", Boolean.TRUE, "replayed_event_count", 0)
                )
            );
            return () -> this.sink = null;
        }

        public String lastRequestJson() {
            return lastRequestJson;
        }

        public void emitEvent(GhoDexGatewayEnvelope envelope) {
            if (sink == null) {
                throw new AssertionError("subscription not open");
            }
            sink.onEnvelope(envelope);
        }
    }
}
