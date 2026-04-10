package com.leongong.ghodex.remote;

import java.util.ArrayList;
import java.util.List;
import java.util.Objects;

public final class GhoDexGatewayRequest {
    private final String requestId;
    private final String command;
    private final String authToken;
    private final String client;
    private final List<String> requestedScopes;
    private final String pairingCode;
    private final String terminalId;
    private final String text;
    private final String commandText;
    private final Long sinceSequence;
    private final Integer eventLimit;
    private final String scope;
    private final String mode;
    private final Integer maxChars;
    private final Integer maxLines;

    private GhoDexGatewayRequest(Builder builder) {
        this.requestId = builder.requestId;
        this.command = builder.command;
        this.authToken = builder.authToken;
        this.client = builder.client;
        this.requestedScopes = List.copyOf(builder.requestedScopes);
        this.pairingCode = builder.pairingCode;
        this.terminalId = builder.terminalId;
        this.text = builder.text;
        this.commandText = builder.commandText;
        this.sinceSequence = builder.sinceSequence;
        this.eventLimit = builder.eventLimit;
        this.scope = builder.scope;
        this.mode = builder.mode;
        this.maxChars = builder.maxChars;
        this.maxLines = builder.maxLines;
    }

    public static GhoDexGatewayRequest pairingBegin(String requestId, String client, List<String> requestedScopes) {
        return builder(requestId, "gateway.pairing.begin")
            .client(client)
            .requestedScopes(requestedScopes)
            .build();
    }

    public static GhoDexGatewayRequest pairingExchange(String requestId, String pairingCode) {
        return builder(requestId, "gateway.pairing.exchange")
            .pairingCode(pairingCode)
            .build();
    }

    public static GhoDexGatewayRequest tokenInfo(String requestId, String authToken) {
        return builder(requestId, "gateway.token.info")
            .authToken(authToken)
            .build();
    }

    public static GhoDexGatewayRequest tokenRotate(String requestId, String authToken) {
        return builder(requestId, "gateway.token.rotate")
            .authToken(authToken)
            .build();
    }

    public static GhoDexGatewayRequest snapshot(String requestId, String authToken) {
        return builder(requestId, "state.snapshot")
            .authToken(authToken)
            .build();
    }

    public static GhoDexGatewayRequest subscribe(String requestId, String authToken, long sinceSequence, int eventLimit) {
        // Keep the long-lived subscription on the legacy command until
        // handle-based `events.stream.*` fully replaces socket-stream semantics
        // for Android clients.
        return builder(requestId, "events.subscribe")
            .authToken(authToken)
            .sinceSequence(sinceSequence)
            .eventLimit(eventLimit)
            .build();
    }

    public static GhoDexGatewayRequest readTerminalSnapshot(
        String requestId,
        String authToken,
        String terminalId,
        String scope,
        int maxLines,
        int maxChars
    ) {
        return builder(requestId, "terminal.read")
            .authToken(authToken)
            .terminalId(terminalId)
            .scope(scope)
            .mode("snapshot")
            .maxLines(maxLines)
            .maxChars(maxChars)
            .build();
    }

    public static GhoDexGatewayRequest sendText(String requestId, String authToken, String terminalId, String text) {
        return builder(requestId, "terminal.write")
            .authToken(authToken)
            .terminalId(terminalId)
            .text(text)
            .build();
    }

    public static GhoDexGatewayRequest runCommand(String requestId, String authToken, String terminalId, String commandText) {
        return builder(requestId, "terminal.command.run")
            .authToken(authToken)
            .terminalId(terminalId)
            .commandText(commandText)
            .build();
    }

    public String toJson() {
        List<String> fields = new ArrayList<>();
        addString(fields, "request_id", requestId);
        addString(fields, "command", command);
        addString(fields, "auth_token", authToken);
        addString(fields, "client", client);
        addStringArray(fields, "requested_scopes", requestedScopes);
        addString(fields, "pairing_code", pairingCode);
        addString(fields, "terminal_id", terminalId);
        addString(fields, "text", text);
        addString(fields, "command_text", commandText);
        addLong(fields, "since_sequence", sinceSequence);
        addInt(fields, "event_limit", eventLimit);
        addString(fields, "scope", scope);
        addString(fields, "mode", mode);
        addInt(fields, "max_chars", maxChars);
        addInt(fields, "max_lines", maxLines);
        return "{" + String.join(",", fields) + "}";
    }

    public String requestId() {
        return requestId;
    }

    public String command() {
        return command;
    }

    public static Builder builder(String requestId, String command) {
        return new Builder(requestId, command);
    }

    private static void addString(List<String> fields, String key, String value) {
        if (value == null) {
            return;
        }
        fields.add(quote(key) + ":" + quote(value));
    }

    private static void addStringArray(List<String> fields, String key, List<String> values) {
        if (values == null || values.isEmpty()) {
            return;
        }
        List<String> quoted = new ArrayList<>();
        for (String value : values) {
            quoted.add(quote(value));
        }
        fields.add(quote(key) + ":[" + String.join(",", quoted) + "]");
    }

    private static void addLong(List<String> fields, String key, Long value) {
        if (value == null) {
            return;
        }
        fields.add(quote(key) + ":" + value);
    }

    private static void addInt(List<String> fields, String key, Integer value) {
        if (value == null) {
            return;
        }
        fields.add(quote(key) + ":" + value);
    }

    private static String quote(String value) {
        StringBuilder out = new StringBuilder();
        out.append('"');
        for (int i = 0; i < value.length(); i += 1) {
            char c = value.charAt(i);
            switch (c) {
            case '\\':
                out.append("\\\\");
                break;
            case '"':
                out.append("\\\"");
                break;
            case '\n':
                out.append("\\n");
                break;
            case '\r':
                out.append("\\r");
                break;
            case '\t':
                out.append("\\t");
                break;
            default:
                if (c < 0x20) {
                    out.append(String.format("\\u%04x", (int) c));
                } else {
                    out.append(c);
                }
                break;
            }
        }
        out.append('"');
        return out.toString();
    }

    public static final class Builder {
        private final String requestId;
        private final String command;
        private String authToken;
        private String client;
        private List<String> requestedScopes = List.of();
        private String pairingCode;
        private String terminalId;
        private String text;
        private String commandText;
        private Long sinceSequence;
        private Integer eventLimit;
        private String scope;
        private String mode;
        private Integer maxChars;
        private Integer maxLines;

        private Builder(String requestId, String command) {
            this.requestId = Objects.requireNonNull(requestId, "requestId");
            this.command = Objects.requireNonNull(command, "command");
        }

        public Builder authToken(String authToken) {
            this.authToken = authToken;
            return this;
        }

        public Builder client(String client) {
            this.client = client;
            return this;
        }

        public Builder requestedScopes(List<String> requestedScopes) {
            this.requestedScopes = requestedScopes == null ? List.of() : List.copyOf(requestedScopes);
            return this;
        }

        public Builder pairingCode(String pairingCode) {
            this.pairingCode = pairingCode;
            return this;
        }

        public Builder terminalId(String terminalId) {
            this.terminalId = terminalId;
            return this;
        }

        public Builder text(String text) {
            this.text = text;
            return this;
        }

        public Builder commandText(String commandText) {
            this.commandText = commandText;
            return this;
        }

        public Builder sinceSequence(long sinceSequence) {
            this.sinceSequence = sinceSequence;
            return this;
        }

        public Builder eventLimit(int eventLimit) {
            this.eventLimit = eventLimit;
            return this;
        }

        public Builder scope(String scope) {
            this.scope = scope;
            return this;
        }

        public Builder mode(String mode) {
            this.mode = mode;
            return this;
        }

        public Builder maxChars(int maxChars) {
            this.maxChars = maxChars;
            return this;
        }

        public Builder maxLines(int maxLines) {
            this.maxLines = maxLines;
            return this;
        }

        public GhoDexGatewayRequest build() {
            return new GhoDexGatewayRequest(this);
        }
    }
}
