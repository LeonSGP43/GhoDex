package com.leongong.ghodex.remote;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

public final class GhoDexGatewayJsonCodec {
    private final String source;
    private int index;

    private GhoDexGatewayJsonCodec(String source) {
        this.source = source;
    }

    public static GhoDexGatewayEnvelope decodeEnvelope(String json) {
        Object value = new GhoDexGatewayJsonCodec(json).parseValue();
        if (!(value instanceof Map<?, ?> map)) {
            throw new IllegalArgumentException("Expected JSON object envelope");
        }

        @SuppressWarnings("unchecked")
        Map<String, Object> object = (Map<String, Object>) map;
        GhoDexGatewayEnvelope.Builder builder = GhoDexGatewayEnvelope.builder()
            .requestId(stringValue(object.get("request_id")))
            .status(stringValue(object.get("status")))
            .errorCode(stringValue(object.get("error_code")))
            .errorMessage(stringValue(object.get("error_message")));

        Map<String, Object> result = objectValue(object.get("result"));
        if (result != null) {
            builder.result(result);
        }

        String event = stringValue(object.get("event"));
        if (event != null) {
            builder.event(event);
        }

        Number sequence = numberValue(object.get("sequence"));
        if (sequence != null) {
            builder.sequence(sequence.longValue());
        }

        Map<String, Object> resource = objectValue(object.get("resource"));
        if (resource != null) {
            builder.resource(
                stringValue(resource.get("type")),
                stringValue(resource.get("id")),
                intValue(resource.get("generation"))
            );
        }

        Boolean gap = booleanValue(object.get("gap"));
        if (gap != null) {
            builder.gap(gap);
        }

        Boolean requiresSnapshotResync = booleanValue(object.get("requires_snapshot_resync"));
        if (requiresSnapshotResync != null) {
            builder.requiresSnapshotResync(requiresSnapshotResync);
        }

        Map<String, Object> payload = objectValue(object.get("payload"));
        if (payload != null) {
            builder.payload(payload);
        }

        return builder.build();
    }

    private static String stringValue(Object value) {
        return value instanceof String ? (String) value : null;
    }

    private static Number numberValue(Object value) {
        return value instanceof Number ? (Number) value : null;
    }

    private static Boolean booleanValue(Object value) {
        return value instanceof Boolean ? (Boolean) value : null;
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> objectValue(Object value) {
        return value instanceof Map<?, ?> ? (Map<String, Object>) value : null;
    }

    private static int intValue(Object value) {
        Number number = numberValue(value);
        return number == null ? 0 : number.intValue();
    }

    private Object parseValue() {
        skipWhitespace();
        if (index >= source.length()) {
            throw new IllegalArgumentException("Unexpected end of JSON");
        }

        char c = source.charAt(index);
        return switch (c) {
            case '{' -> parseObject();
            case '[' -> parseArray();
            case '"' -> parseString();
            case 't' -> parseLiteral("true", Boolean.TRUE);
            case 'f' -> parseLiteral("false", Boolean.FALSE);
            case 'n' -> parseLiteral("null", null);
            default -> parseNumber();
        };
    }

    private Map<String, Object> parseObject() {
        expect('{');
        skipWhitespace();
        Map<String, Object> object = new LinkedHashMap<>();
        if (peek('}')) {
            expect('}');
            return object;
        }

        while (true) {
            String key = parseString();
            skipWhitespace();
            expect(':');
            Object value = parseValue();
            object.put(key, value);
            skipWhitespace();
            if (peek('}')) {
                expect('}');
                return object;
            }
            expect(',');
        }
    }

    private List<Object> parseArray() {
        expect('[');
        skipWhitespace();
        List<Object> array = new ArrayList<>();
        if (peek(']')) {
            expect(']');
            return array;
        }

        while (true) {
            array.add(parseValue());
            skipWhitespace();
            if (peek(']')) {
                expect(']');
                return array;
            }
            expect(',');
        }
    }

    private String parseString() {
        expect('"');
        StringBuilder out = new StringBuilder();
        while (index < source.length()) {
            char c = source.charAt(index++);
            if (c == '"') {
                return out.toString();
            }
            if (c != '\\') {
                out.append(c);
                continue;
            }
            if (index >= source.length()) {
                throw new IllegalArgumentException("Invalid escape sequence");
            }
            char escaped = source.charAt(index++);
            switch (escaped) {
                case '"':
                case '\\':
                case '/':
                    out.append(escaped);
                    break;
                case 'b':
                    out.append('\b');
                    break;
                case 'f':
                    out.append('\f');
                    break;
                case 'n':
                    out.append('\n');
                    break;
                case 'r':
                    out.append('\r');
                    break;
                case 't':
                    out.append('\t');
                    break;
                case 'u':
                    if (index + 4 > source.length()) {
                        throw new IllegalArgumentException("Invalid unicode escape");
                    }
                    String hex = source.substring(index, index + 4);
                    out.append((char) Integer.parseInt(hex, 16));
                    index += 4;
                    break;
                default:
                    throw new IllegalArgumentException("Unsupported escape: \\" + escaped);
            }
        }
        throw new IllegalArgumentException("Unterminated string");
    }

    private Object parseLiteral(String literal, Object value) {
        if (!source.startsWith(literal, index)) {
            throw new IllegalArgumentException("Expected " + literal);
        }
        index += literal.length();
        return value;
    }

    private Number parseNumber() {
        int start = index;
        if (source.charAt(index) == '-') {
            index += 1;
        }
        while (index < source.length() && Character.isDigit(source.charAt(index))) {
            index += 1;
        }
        boolean isDouble = false;
        if (index < source.length() && source.charAt(index) == '.') {
            isDouble = true;
            index += 1;
            while (index < source.length() && Character.isDigit(source.charAt(index))) {
                index += 1;
            }
        }
        if (index < source.length() && (source.charAt(index) == 'e' || source.charAt(index) == 'E')) {
            isDouble = true;
            index += 1;
            if (index < source.length() && (source.charAt(index) == '+' || source.charAt(index) == '-')) {
                index += 1;
            }
            while (index < source.length() && Character.isDigit(source.charAt(index))) {
                index += 1;
            }
        }

        String token = source.substring(start, index);
        return isDouble ? Double.parseDouble(token) : Long.parseLong(token);
    }

    private void expect(char expected) {
        skipWhitespace();
        if (index >= source.length() || source.charAt(index) != expected) {
            throw new IllegalArgumentException("Expected '" + expected + "'");
        }
        index += 1;
    }

    private boolean peek(char c) {
        skipWhitespace();
        return index < source.length() && source.charAt(index) == c;
    }

    private void skipWhitespace() {
        while (index < source.length()) {
            char c = source.charAt(index);
            if (!Character.isWhitespace(c)) {
                return;
            }
            index += 1;
        }
    }
}
