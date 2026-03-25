package com.leongong.ghodex.remote;

import java.util.Collection;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
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
            existing == null ? null : existing.getTitle(),
            existing == null ? null : existing.getWorkingDirectory(),
            existing != null && existing.isFocused(),
            existing != null && existing.isVisible(),
            envelope.getEvent(),
            envelope.getPayload()
        );
        terminals.put(terminalId, next);
    }

    public void applySnapshotEnvelope(GhoDexGatewayEnvelope envelope) {
        terminals.clear();
        snapshotResyncRequired = false;

        for (Map<String, Object> tab : envelope.resultObjectList("tabs")) {
            applySnapshotTab(tab);
        }

        Long snapshotSequence = envelope.resultLong("last_sequence");
        if (snapshotSequence != null) {
            lastSequence = Math.max(lastSequence, snapshotSequence);
        }
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
        private final String title;
        private final String workingDirectory;
        private final boolean focused;
        private final boolean visible;
        private final String lastEvent;
        private final Map<String, Object> lastPayload;

        private TerminalEntry(
            String terminalId,
            int generation,
            String title,
            String workingDirectory,
            boolean focused,
            boolean visible,
            String lastEvent,
            Map<String, Object> lastPayload
        ) {
            this.terminalId = terminalId;
            this.generation = generation;
            this.title = title;
            this.workingDirectory = workingDirectory;
            this.focused = focused;
            this.visible = visible;
            this.lastEvent = lastEvent;
            this.lastPayload = Collections.unmodifiableMap(new LinkedHashMap<>(lastPayload));
        }

        public String getTerminalId() {
            return terminalId;
        }

        public int getGeneration() {
            return generation;
        }

        public String getTitle() {
            return title;
        }

        public String getWorkingDirectory() {
            return workingDirectory;
        }

        public boolean isFocused() {
            return focused;
        }

        public boolean isVisible() {
            return visible;
        }

        public String getLastEvent() {
            return lastEvent;
        }

        public Map<String, Object> getLastPayload() {
            return lastPayload;
        }
    }

    @SuppressWarnings("unchecked")
    private void applySnapshotTab(Map<String, Object> tab) {
        Object terminalsValue = tab.get("terminals");
        if (!(terminalsValue instanceof List<?> terminalList)) {
            return;
        }

        for (Object terminalValue : terminalList) {
            if (!(terminalValue instanceof Map<?, ?> rawTerminal)) {
                continue;
            }

            Map<String, Object> terminal = (Map<String, Object>) rawTerminal;
            String terminalId = stringValue(terminal.get("terminal_id"));
            if (terminalId == null || terminalId.isBlank()) {
                continue;
            }

            terminals.put(
                terminalId,
                new TerminalEntry(
                    terminalId,
                    intValue(terminal.get("generation")),
                    stringValue(terminal.get("title")),
                    stringValue(terminal.get("working_directory")),
                    booleanValue(terminal.get("is_focused")),
                    booleanValue(terminal.get("is_visible")),
                    "snapshot",
                    Map.of()
                )
            );
        }
    }

    private static String stringValue(Object value) {
        return value instanceof String ? (String) value : null;
    }

    private static int intValue(Object value) {
        return value instanceof Number number ? number.intValue() : 0;
    }

    private static boolean booleanValue(Object value) {
        return value instanceof Boolean bool && bool;
    }
}
