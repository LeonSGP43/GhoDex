package com.leongong.ghodex.androidapp;

import android.net.Uri;
import org.json.JSONException;
import org.json.JSONObject;

record GatewayQrPayload(
    String host,
    int port,
    String pairingCode
) {
    private static final String EXPECTED_KIND = "ghodex.gateway.pairing";

    static GatewayQrPayload parse(String rawPayload) {
        if (rawPayload == null || rawPayload.isBlank()) {
            throw new IllegalArgumentException("QR payload is empty");
        }

        String trimmed = rawPayload.trim();
        if (trimmed.startsWith("{")) {
            return parseJson(trimmed);
        }
        return parseUri(trimmed);
    }

    private static GatewayQrPayload parseJson(String rawPayload) {
        try {
            JSONObject object = new JSONObject(rawPayload);
            String kind = object.optString("kind", "");
            if (!EXPECTED_KIND.equals(kind)) {
                throw new IllegalArgumentException("QR kind is not a GhoDex pairing payload");
            }

            return new GatewayQrPayload(
                requireNonBlank(object.optString("host", ""), "QR host is missing"),
                requirePort(object.optInt("port", 0)),
                requireNonBlank(object.optString("pairing_code", ""), "QR pairing code is missing")
            );
        } catch (JSONException e) {
            throw new IllegalArgumentException("QR payload is not valid JSON", e);
        }
    }

    private static GatewayQrPayload parseUri(String rawPayload) {
        Uri uri = Uri.parse(rawPayload);
        if (!"ghodex".equals(uri.getScheme())) {
            throw new IllegalArgumentException("QR scheme is not supported");
        }
        String authority = uri.getAuthority();
        if (!"pair".equals(authority) && !"pairing".equals(authority)) {
            throw new IllegalArgumentException("QR route is not a pairing payload");
        }

        return new GatewayQrPayload(
            requireNonBlank(uri.getQueryParameter("host"), "QR host is missing"),
            requirePort(parsePort(uri.getQueryParameter("port"))),
            requireNonBlank(uri.getQueryParameter("pairing_code"), "QR pairing code is missing")
        );
    }

    private static int parsePort(String rawPort) {
        if (rawPort == null || rawPort.isBlank()) {
            return 0;
        }
        try {
            return Integer.parseInt(rawPort.trim());
        } catch (NumberFormatException e) {
            throw new IllegalArgumentException("QR port is invalid", e);
        }
    }

    private static int requirePort(int port) {
        if (port < 1 || port > 65_535) {
            throw new IllegalArgumentException("QR port is invalid");
        }
        return port;
    }

    private static String requireNonBlank(String value, String message) {
        if (value == null || value.isBlank()) {
            throw new IllegalArgumentException(message);
        }
        return value.trim();
    }
}
