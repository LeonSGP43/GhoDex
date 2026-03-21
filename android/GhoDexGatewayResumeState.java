import java.util.LinkedHashSet;
import java.util.Set;

public final class GhoDexGatewayResumeState {
    private String authToken;
    private long sinceSequence;
    private final Set<String> observedTerminalIds = new LinkedHashSet<>();

    public void setAuthToken(String authToken) {
        this.authToken = authToken;
    }

    public String getAuthToken() {
        return authToken;
    }

    public long getSinceSequence() {
        return sinceSequence;
    }

    public void advanceSequence(long nextSequence) {
        if (nextSequence > sinceSequence) {
            sinceSequence = nextSequence;
        }
    }

    public void observeTerminal(String terminalId) {
        if (terminalId != null && !terminalId.isBlank()) {
            observedTerminalIds.add(terminalId);
        }
    }

    public void stopObservingTerminal(String terminalId) {
        observedTerminalIds.remove(terminalId);
    }

    public Set<String> observedTerminalIds() {
        return Set.copyOf(observedTerminalIds);
    }

    public GhoDexGatewayRequest subscribeRequest(String requestId, int eventLimit) {
        return GhoDexGatewayRequest.subscribe(requestId, authToken, sinceSequence, eventLimit);
    }

    public GhoDexGatewayRequest snapshotRequest(String requestId) {
        return GhoDexGatewayRequest.snapshot(requestId, authToken);
    }
}
