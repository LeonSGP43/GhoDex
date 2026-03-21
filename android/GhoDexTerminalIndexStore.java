import java.util.Collection;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;

public final class GhoDexTerminalIndexStore {
    private final Map<String, TerminalEntry> terminals = new LinkedHashMap<>();
    private long lastSequence;
    private boolean snapshotResyncRequired;

    public void applyEnvelope(GhoDexGatewayEnvelope envelope) {
        if (!envelope.isEvent()) {
            return;
        }

        lastSequence = Math.max(lastSequence, envelope.getSequence());
        if (envelope.requiresSnapshotResync()) {
            snapshotResyncRequired = true;
            return;
        }

        if (!"terminal".equals(envelope.getResourceType())) {
            return;
        }

        String terminalId = envelope.getResourceId();
        if (terminalId == null || terminalId.isBlank()) {
            return;
        }

        TerminalEntry existing = terminals.get(terminalId);
        TerminalEntry next = new TerminalEntry(
            terminalId,
            Math.max(envelope.getResourceGeneration(), existing == null ? 0 : existing.getGeneration()),
            envelope.getEvent(),
            envelope.getPayload()
        );
        terminals.put(terminalId, next);
    }

    public void resetForSnapshot() {
        snapshotResyncRequired = false;
    }

    public long getLastSequence() {
        return lastSequence;
    }

    public boolean isSnapshotResyncRequired() {
        return snapshotResyncRequired;
    }

    public TerminalEntry getTerminal(String terminalId) {
        return terminals.get(terminalId);
    }

    public Collection<TerminalEntry> terminals() {
        return Collections.unmodifiableCollection(terminals.values());
    }

    public static final class TerminalEntry {
        private final String terminalId;
        private final int generation;
        private final String lastEvent;
        private final Map<String, Object> lastPayload;

        private TerminalEntry(
            String terminalId,
            int generation,
            String lastEvent,
            Map<String, Object> lastPayload
        ) {
            this.terminalId = terminalId;
            this.generation = generation;
            this.lastEvent = lastEvent;
            this.lastPayload = Collections.unmodifiableMap(new LinkedHashMap<>(lastPayload));
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

        public Map<String, Object> getLastPayload() {
            return lastPayload;
        }
    }
}
