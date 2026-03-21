import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

public final class GhoDexGatewayEnvelope {
    private final String requestId;
    private final String status;
    private final String errorCode;
    private final String errorMessage;
    private final Map<String, Object> result;
    private final String event;
    private final Long sequence;
    private final String resourceType;
    private final String resourceId;
    private final Integer resourceGeneration;
    private final boolean gap;
    private final boolean requiresSnapshotResync;
    private final Map<String, Object> payload;

    private GhoDexGatewayEnvelope(Builder builder) {
        this.requestId = builder.requestId;
        this.status = builder.status;
        this.errorCode = builder.errorCode;
        this.errorMessage = builder.errorMessage;
        this.result = immutableCopy(builder.result);
        this.event = builder.event;
        this.sequence = builder.sequence;
        this.resourceType = builder.resourceType;
        this.resourceId = builder.resourceId;
        this.resourceGeneration = builder.resourceGeneration;
        this.gap = builder.gap;
        this.requiresSnapshotResync = builder.requiresSnapshotResync;
        this.payload = immutableCopy(builder.payload);
    }

    public static GhoDexGatewayEnvelope ok(String requestId, Map<String, Object> result) {
        return builder()
            .requestId(requestId)
            .status("ok")
            .result(result)
            .build();
    }

    public static GhoDexGatewayEnvelope error(String requestId, String errorCode, String errorMessage) {
        return builder()
            .requestId(requestId)
            .status("error")
            .errorCode(errorCode)
            .errorMessage(errorMessage)
            .build();
    }

    public static GhoDexGatewayEnvelope event(
        long sequence,
        String event,
        String resourceType,
        String resourceId,
        int resourceGeneration,
        Map<String, Object> payload
    ) {
        return builder()
            .sequence(sequence)
            .event(event)
            .resource(resourceType, resourceId, resourceGeneration)
            .payload(payload)
            .build();
    }

    public static GhoDexGatewayEnvelope overflow(long sequence, int droppedEvents) {
        return builder()
            .sequence(sequence)
            .event("overflow")
            .gap(true)
            .requiresSnapshotResync(true)
            .payload(Map.of("dropped_events", droppedEvents))
            .build();
    }

    public static Builder builder() {
        return new Builder();
    }

    public boolean isOk() {
        return "ok".equals(status);
    }

    public boolean isError() {
        return "error".equals(status);
    }

    public boolean isEvent() {
        return event != null;
    }

    public String getRequestId() {
        return requestId;
    }

    public String getStatus() {
        return status;
    }

    public String getErrorCode() {
        return errorCode;
    }

    public String getErrorMessage() {
        return errorMessage;
    }

    public String getEvent() {
        return event;
    }

    public long getSequence() {
        return sequence == null ? 0L : sequence;
    }

    public boolean isGap() {
        return gap;
    }

    public boolean requiresSnapshotResync() {
        return requiresSnapshotResync;
    }

    public String getResourceType() {
        return resourceType;
    }

    public String getResourceId() {
        return resourceId;
    }

    public int getResourceGeneration() {
        return resourceGeneration == null ? 0 : resourceGeneration;
    }

    public Map<String, Object> getResult() {
        return result;
    }

    public Map<String, Object> getPayload() {
        return payload;
    }

    public String resultString(String key) {
        Object value = result.get(key);
        return value instanceof String ? (String) value : null;
    }

    @SuppressWarnings("unchecked")
    public List<String> resultStringList(String key) {
        Object value = result.get(key);
        if (value instanceof List<?>) {
            return (List<String>) value;
        }
        return List.of();
    }

    private static Map<String, Object> immutableCopy(Map<String, Object> map) {
        if (map == null || map.isEmpty()) {
            return Collections.emptyMap();
        }
        return Collections.unmodifiableMap(new LinkedHashMap<>(map));
    }

    public static final class Builder {
        private String requestId;
        private String status;
        private String errorCode;
        private String errorMessage;
        private Map<String, Object> result = Map.of();
        private String event;
        private Long sequence;
        private String resourceType;
        private String resourceId;
        private Integer resourceGeneration;
        private boolean gap;
        private boolean requiresSnapshotResync;
        private Map<String, Object> payload = Map.of();

        public Builder requestId(String requestId) {
            this.requestId = requestId;
            return this;
        }

        public Builder status(String status) {
            this.status = status;
            return this;
        }

        public Builder errorCode(String errorCode) {
            this.errorCode = errorCode;
            return this;
        }

        public Builder errorMessage(String errorMessage) {
            this.errorMessage = errorMessage;
            return this;
        }

        public Builder result(Map<String, Object> result) {
            this.result = result == null ? Map.of() : result;
            return this;
        }

        public Builder event(String event) {
            this.event = event;
            return this;
        }

        public Builder sequence(long sequence) {
            this.sequence = sequence;
            return this;
        }

        public Builder resource(String type, String id, int generation) {
            this.resourceType = type;
            this.resourceId = id;
            this.resourceGeneration = generation;
            return this;
        }

        public Builder gap(boolean gap) {
            this.gap = gap;
            return this;
        }

        public Builder requiresSnapshotResync(boolean requiresSnapshotResync) {
            this.requiresSnapshotResync = requiresSnapshotResync;
            return this;
        }

        public Builder payload(Map<String, Object> payload) {
            this.payload = payload == null ? Map.of() : payload;
            return this;
        }

        public GhoDexGatewayEnvelope build() {
            return new GhoDexGatewayEnvelope(this);
        }
    }
}
