import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.function.BooleanSupplier;

public final class GhoDexGatewayContractSelfTest {
    public static void main(String[] args) throws Exception {
        pairingBeginSerializesScopes();
        subscribeUsesMonotonicResumeSequence();
        sendTextEscapesNewlines();
        readTerminalSnapshotCarriesWindowArgs();
        clientStateMachinePersistsPairingAndSnapshotState();
        subscriptionEventsUpdateTerminalIndexAndRequireResync();
        tcpTransportAndUiStoreRoundTrip();
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

    private static void tcpTransportAndUiStoreRoundTrip() throws Exception {
        try (FakeGatewayServer server = new FakeGatewayServer()) {
            GhoDexGatewaySessionStore sessionStore = new GhoDexGatewaySessionStore();
            GhoDexTerminalIndexStore terminalIndexStore = new GhoDexTerminalIndexStore();
            GhoDexGatewayClientStateMachine stateMachine = new GhoDexGatewayClientStateMachine(
                new GhoDexGatewayTcpTransport("127.0.0.1", server.port()),
                sessionStore,
                terminalIndexStore
            );
            GhoDexGatewayUiStore uiStore = new GhoDexGatewayUiStore();
            stateMachine.addStateListener(uiStore);

            String pairingCode = stateMachine.beginPairing("req-live-pair-begin", "android-live", List.of("observe"));
            assertEquals("PAIR-LIVE", pairingCode);
            assertEquals("PAIR-LIVE", uiStore.snapshot().getPairingCode());

            String authToken = stateMachine.exchangePairing("req-live-pair-exchange", pairingCode);
            assertEquals("token-live", authToken);
            assertTrue(uiStore.snapshot().isAuthTokenPresent(), "ui store should reflect active token");

            stateMachine.refreshSnapshot("req-live-snapshot");
            assertEquals("1.0", uiStore.snapshot().getProtocolVersion());

            stateMachine.observeTerminal("terminal-live");
            stateMachine.openSubscription("req-live-subscribe", 32);

            waitUntil(
                () -> uiStore.snapshot().isSnapshotResyncRequired(),
                "ui store should receive overflow resync from live tcp transport"
            );

            GhoDexGatewayUiSnapshot snapshot = uiStore.snapshot();
            assertTrue(snapshot.isSubscriptionOpen(), "subscription should be marked open");
            assertEquals(List.of("observe"), snapshot.getScopes());
            assertEquals(List.of("terminal-live"), snapshot.getObservedTerminalIds());
            assertEquals(1, snapshot.getTerminals().size());
            assertEquals("terminal.input.sent", snapshot.getTerminals().get(0).getLastEvent());
            assertEquals(3, snapshot.getTerminals().get(0).getGeneration());
            assertEquals(8L, sessionStore.resumeState().getSinceSequence());

            stateMachine.closeSubscription();
        }
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

    private static void waitUntil(BooleanSupplier condition, String message) throws InterruptedException {
        long deadline = System.currentTimeMillis() + 2_000;
        while (System.currentTimeMillis() < deadline) {
            if (condition.getAsBoolean()) {
                return;
            }
            Thread.sleep(20);
        }
        throw new AssertionError(message);
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

    private static final class FakeGatewayServer implements AutoCloseable {
        private final ServerSocket serverSocket;
        private final Thread acceptThread;
        private final AtomicBoolean running = new AtomicBoolean(true);

        private FakeGatewayServer() throws IOException {
            this.serverSocket = new ServerSocket(0);
            this.acceptThread = new Thread(this::acceptLoop, "ghodex-fake-gateway-server");
            this.acceptThread.setDaemon(true);
            this.acceptThread.start();
        }

        int port() {
            return serverSocket.getLocalPort();
        }

        @Override
        public void close() throws Exception {
            running.set(false);
            serverSocket.close();
            acceptThread.join(500);
        }

        private void acceptLoop() {
            while (running.get()) {
                try {
                    Socket socket = serverSocket.accept();
                    handle(socket);
                } catch (IOException ignored) {
                    return;
                }
            }
        }

        private void handle(Socket socket) {
            try (socket) {
                String request = readAll(socket.getInputStream());
                String requestId = extractField(request, "request_id");
                String command = extractField(request, "command");
                OutputStream outputStream = socket.getOutputStream();

                switch (command) {
                    case "gateway.pairing.begin" -> {
                        writeLine(
                            outputStream,
                            "{\"request_id\":\"" + requestId + "\",\"status\":\"ok\",\"result\":{\"pairing_code\":\"PAIR-LIVE\"}}"
                        );
                    }
                    case "gateway.pairing.exchange" -> {
                        writeLine(
                            outputStream,
                            "{\"request_id\":\"" + requestId + "\",\"status\":\"ok\",\"result\":{\"auth_token\":\"token-live\",\"token_id\":\"tok-live\",\"scopes\":[\"observe\"]}}"
                        );
                    }
                    case "snapshot" -> {
                        writeLine(
                            outputStream,
                            "{\"request_id\":\"" + requestId + "\",\"status\":\"ok\",\"result\":{\"protocol_version\":\"1.0\"}}"
                        );
                    }
                    case "events.subscribe" -> {
                        writeLine(
                            outputStream,
                            "{\"request_id\":\"" + requestId + "\",\"status\":\"ok\",\"result\":{\"live_stream_open\":true,\"replayed_event_count\":0}}"
                        );
                        writeLine(
                            outputStream,
                            "{\"sequence\":7,\"event\":\"terminal.input.sent\",\"resource\":{\"type\":\"terminal\",\"id\":\"terminal-live\",\"generation\":3},\"payload\":{\"text_length\":4}}"
                        );
                        writeLine(
                            outputStream,
                            "{\"sequence\":8,\"event\":\"overflow\",\"gap\":true,\"requires_snapshot_resync\":true,\"payload\":{\"dropped_events\":5}}"
                        );
                    }
                    case "read-terminal", "send-text", "run-command" -> {
                        writeLine(
                            outputStream,
                            "{\"request_id\":\"" + requestId + "\",\"status\":\"ok\",\"result\":{\"accepted\":true}}"
                        );
                    }
                    default -> {
                        writeLine(
                            outputStream,
                            "{\"request_id\":\"" + requestId + "\",\"status\":\"error\",\"error_code\":\"unsupported\",\"error_message\":\"" + command + "\"}"
                        );
                    }
                }
            } catch (IOException e) {
                throw new IllegalStateException("fake gateway server failed", e);
            }
        }

        private static String extractField(String json, String key) {
            String needle = "\"" + key + "\":\"";
            int start = json.indexOf(needle);
            if (start == -1) {
                return "";
            }
            int valueStart = start + needle.length();
            int valueEnd = json.indexOf('"', valueStart);
            return valueEnd == -1 ? "" : json.substring(valueStart, valueEnd);
        }

        private static String readAll(InputStream inputStream) throws IOException {
            ByteArrayOutputStream buffer = new ByteArrayOutputStream();
            inputStream.transferTo(buffer);
            return buffer.toString(StandardCharsets.UTF_8);
        }

        private static void writeLine(OutputStream outputStream, String line) throws IOException {
            outputStream.write(line.getBytes(StandardCharsets.UTF_8));
            outputStream.write('\n');
            outputStream.flush();
        }
    }
}
