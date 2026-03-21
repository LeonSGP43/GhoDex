import java.util.List;

public final class GhoDexGatewayContractSelfTest {
    public static void main(String[] args) {
        pairingBeginSerializesScopes();
        subscribeUsesMonotonicResumeSequence();
        sendTextEscapesNewlines();
        readTerminalSnapshotCarriesWindowArgs();
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

    private static void assertContains(String haystack, String needle) {
        if (!haystack.contains(needle)) {
            throw new AssertionError("Expected to find " + needle + " in " + haystack);
        }
    }
}
