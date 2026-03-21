import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

public final class GhoDexGatewayUiSnapshot {
    private final String pairingCode;
    private final boolean authTokenPresent;
    private final String tokenId;
    private final String protocolVersion;
    private final boolean subscriptionOpen;
    private final boolean snapshotResyncRequired;
    private final List<String> scopes;
    private final List<String> observedTerminalIds;
    private final List<TerminalRow> terminals;

    public GhoDexGatewayUiSnapshot(
        String pairingCode,
        boolean authTokenPresent,
        String tokenId,
        String protocolVersion,
        boolean subscriptionOpen,
        boolean snapshotResyncRequired,
        List<String> scopes,
        List<String> observedTerminalIds,
        List<TerminalRow> terminals
    ) {
        this.pairingCode = pairingCode;
        this.authTokenPresent = authTokenPresent;
        this.tokenId = tokenId;
        this.protocolVersion = protocolVersion;
        this.subscriptionOpen = subscriptionOpen;
        this.snapshotResyncRequired = snapshotResyncRequired;
        this.scopes = Collections.unmodifiableList(new ArrayList<>(scopes));
        this.observedTerminalIds = Collections.unmodifiableList(new ArrayList<>(observedTerminalIds));
        this.terminals = Collections.unmodifiableList(new ArrayList<>(terminals));
    }

    public String getPairingCode() {
        return pairingCode;
    }

    public boolean isAuthTokenPresent() {
        return authTokenPresent;
    }

    public String getTokenId() {
        return tokenId;
    }

    public String getProtocolVersion() {
        return protocolVersion;
    }

    public boolean isSubscriptionOpen() {
        return subscriptionOpen;
    }

    public boolean isSnapshotResyncRequired() {
        return snapshotResyncRequired;
    }

    public List<String> getScopes() {
        return scopes;
    }

    public List<String> getObservedTerminalIds() {
        return observedTerminalIds;
    }

    public List<TerminalRow> getTerminals() {
        return terminals;
    }

    public static final class TerminalRow {
        private final String terminalId;
        private final int generation;
        private final String lastEvent;

        public TerminalRow(String terminalId, int generation, String lastEvent) {
            this.terminalId = terminalId;
            this.generation = generation;
            this.lastEvent = lastEvent;
        }

        public String getTerminalId() {
            return terminalId;
        }

        public int getGeneration() {
            return generation;
        }

        public String getLastEvent() {
            return lastEvent;
        }
    }
}
