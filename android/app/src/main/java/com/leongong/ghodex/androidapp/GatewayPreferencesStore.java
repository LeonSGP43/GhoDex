package com.leongong.ghodex.androidapp;

import android.content.Context;
import android.content.SharedPreferences;
import com.leongong.ghodex.remote.GhoDexGatewaySessionStore;
import java.util.Arrays;
import java.util.List;
import java.util.stream.Collectors;

final class GatewayPreferencesStore {
    private static final String PREFS_NAME = "ghodex_remote_gateway";
    private static final String KEY_HOST = "host";
    private static final String KEY_PORT = "port";
    private static final String KEY_PAIRING_CODE = "pairing_code";
    private static final String KEY_AUTH_TOKEN = "auth_token";
    private static final String KEY_TOKEN_ID = "token_id";
    private static final String KEY_SCOPES = "scopes";
    private static final String KEY_OBSERVED_TERMINAL_ID = "observed_terminal_id";

    private final SharedPreferences sharedPreferences;

    GatewayPreferencesStore(Context context) {
        this.sharedPreferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
    }

    StoredState load() {
        String scopesRaw = sharedPreferences.getString(KEY_SCOPES, "");
        List<String> scopes = scopesRaw == null || scopesRaw.isBlank()
            ? List.of()
            : Arrays.stream(scopesRaw.split(","))
                .map(String::trim)
                .filter(value -> !value.isEmpty())
                .collect(Collectors.toList());

        return new StoredState(
            sharedPreferences.getString(KEY_HOST, "127.0.0.1"),
            sharedPreferences.getInt(KEY_PORT, 45777),
            sharedPreferences.getString(KEY_PAIRING_CODE, null),
            sharedPreferences.getString(KEY_AUTH_TOKEN, null),
            sharedPreferences.getString(KEY_TOKEN_ID, null),
            scopes,
            sharedPreferences.getString(KEY_OBSERVED_TERMINAL_ID, null)
        );
    }

    void saveConnection(String host, int port) {
        sharedPreferences.edit()
            .putString(KEY_HOST, host)
            .putInt(KEY_PORT, port)
            .apply();
    }

    void saveSession(
        String pairingCode,
        String authToken,
        String tokenId,
        List<String> scopes,
        String observedTerminalId
    ) {
        sharedPreferences.edit()
            .putString(KEY_PAIRING_CODE, pairingCode)
            .putString(KEY_AUTH_TOKEN, authToken)
            .putString(KEY_TOKEN_ID, tokenId)
            .putString(KEY_SCOPES, String.join(",", scopes))
            .putString(KEY_OBSERVED_TERMINAL_ID, observedTerminalId)
            .apply();
    }

    record StoredState(
        String host,
        int port,
        String pairingCode,
        String authToken,
        String tokenId,
        List<String> scopes,
        String observedTerminalId
    ) {
        void seedSessionStore(GhoDexGatewaySessionStore sessionStore) {
            if (pairingCode != null && !pairingCode.isBlank()) {
                sessionStore.recordPairingCode(pairingCode);
            }
            if (authToken != null && !authToken.isBlank()) {
                sessionStore.activateToken(
                    authToken,
                    tokenId == null || tokenId.isBlank() ? "restored-token" : tokenId,
                    scopes == null ? List.of() : scopes
                );
            }
        }
    }
}
