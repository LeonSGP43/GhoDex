package com.leongong.ghodex.androidapp;

import android.app.Activity;
import android.os.Bundle;
import android.text.InputType;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import com.leongong.ghodex.remote.GhoDexGatewayClientStateMachine;
import com.leongong.ghodex.remote.GhoDexGatewaySessionStore;
import com.leongong.ghodex.remote.GhoDexGatewayTcpTransport;
import com.leongong.ghodex.remote.GhoDexGatewayUiSnapshot;
import com.leongong.ghodex.remote.GhoDexGatewayUiStore;
import com.leongong.ghodex.remote.GhoDexTerminalIndexStore;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicLong;

public final class MainActivity extends Activity {
    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private final AtomicLong requestCounter = new AtomicLong(1);

    private GatewayPreferencesStore preferencesStore;

    private EditText hostInput;
    private EditText portInput;
    private EditText pairingCodeInput;
    private EditText authTokenInput;
    private EditText terminalIdInput;
    private EditText sendTextInput;
    private TextView statusView;
    private TextView stateView;

    private String currentHost;
    private int currentPort;
    private GhoDexGatewaySessionStore sessionStore;
    private GhoDexTerminalIndexStore terminalIndexStore;
    private GhoDexGatewayUiStore uiStore;
    private GhoDexGatewayClientStateMachine stateMachine;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        preferencesStore = new GatewayPreferencesStore(this);
        setContentView(buildContentView());
        restoreInputs();
        ensureStateMachine(true);
        renderSnapshot();
        setStatus("Ready");
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        if (stateMachine != null) {
            stateMachine.closeSubscription();
        }
        executor.shutdownNow();
    }

    private View buildContentView() {
        ScrollView scrollView = new ScrollView(this);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        int padding = dp(16);
        root.setPadding(padding, padding, padding, padding);

        statusView = addLabel(root, "Status: booting");
        hostInput = addEditText(root, "Host");
        portInput = addNumericEditText(root, "Port");
        pairingCodeInput = addEditText(root, "Pairing code");
        authTokenInput = addEditText(root, "Auth token");
        terminalIdInput = addEditText(root, "Observed terminal id");
        sendTextInput = addEditText(root, "Text to send");

        addButton(root, "Begin Pairing", ignored -> runAction("begin pairing", () -> {
            captureConnectionInputs();
            ensureStateMachine(false);
            String pairingCode = stateMachine.beginPairing(nextRequestId("pair-begin"), "android-app", List.of("observe", "mutate"));
            runOnUiThread(() -> pairingCodeInput.setText(pairingCode));
        }));

        addButton(root, "Exchange Pairing", ignored -> {
            captureConnectionInputs();
            String pairingCode = pairingCodeInput.getText().toString().trim();
            runAction("exchange pairing", () -> {
            ensureStateMachine(false);
            String authToken = stateMachine.exchangePairing(
                nextRequestId("pair-exchange"),
                pairingCode
            );
            runOnUiThread(() -> authTokenInput.setText(authToken));
            });
        });

        addButton(root, "Refresh Snapshot", ignored -> runAction("refresh snapshot", () -> {
            captureConnectionInputs();
            ensureStateMachine(false);
            stateMachine.refreshSnapshot(nextRequestId("snapshot"));
            runOnUiThread(this::autofillTerminalIdIfNeeded);
        }));

        addButton(root, "Observe Terminal", ignored -> {
            captureConnectionInputs();
            String terminalId = terminalIdInput.getText().toString().trim();
            runAction("observe terminal", () -> {
            ensureStateMachine(false);
            requireNonEmpty(terminalId, "Terminal id is empty");
            stateMachine.observeTerminal(terminalId);
            });
        });

        addButton(root, "Toggle Subscription", ignored -> {
            captureConnectionInputs();
            String terminalId = terminalIdInput.getText().toString().trim();
            runAction("toggle subscription", () -> {
            ensureStateMachine(false);
            if (sessionStore.isSubscriptionOpen()) {
                stateMachine.closeSubscription();
                return;
            }
            requireNonEmpty(terminalId, "Terminal id is empty");
            stateMachine.observeTerminal(terminalId);
            stateMachine.openSubscription(nextRequestId("subscribe"), 128);
            });
        });

        addButton(root, "Send Text", ignored -> {
            captureConnectionInputs();
            String terminalId = terminalIdInput.getText().toString().trim();
            String text = sendTextInput.getText().toString();
            runAction("send text", () -> {
            ensureStateMachine(false);
            requireNonEmpty(terminalId, "Terminal id is empty");
            requireNonEmpty(text, "Text input is empty");
            String sendText = text.endsWith("\n") ? text : text + "\n";
            stateMachine.sendText(nextRequestId("send-text"), terminalId, sendText);
            });
        });

        stateView = addLabel(root, "");
        stateView.setTextIsSelectable(true);

        scrollView.addView(root);
        return scrollView;
    }

    private void restoreInputs() {
        GatewayPreferencesStore.StoredState storedState = preferencesStore.load();
        hostInput.setText(storedState.host());
        portInput.setText(Integer.toString(storedState.port()));
        if (storedState.pairingCode() != null) {
            pairingCodeInput.setText(storedState.pairingCode());
        }
        if (storedState.authToken() != null) {
            authTokenInput.setText(storedState.authToken());
        }
        if (storedState.observedTerminalId() != null) {
            terminalIdInput.setText(storedState.observedTerminalId());
        }
    }

    private void ensureStateMachine(boolean force) {
        GatewayPreferencesStore.StoredState storedState = preferencesStore.load();
        String host = storedState.host();
        if (host.isEmpty()) {
            host = "127.0.0.1";
        }
        int port = storedState.port();

        if (!force && stateMachine != null && host.equals(currentHost) && port == currentPort) {
            return;
        }

        if (stateMachine != null) {
            stateMachine.closeSubscription();
        }

        currentHost = host;
        currentPort = port;

        sessionStore = new GhoDexGatewaySessionStore();
        terminalIndexStore = new GhoDexTerminalIndexStore();
        uiStore = new GhoDexGatewayUiStore();
        storedState.seedSessionStore(sessionStore);

        String observedTerminalId = storedState.observedTerminalId();
        if (observedTerminalId != null && !observedTerminalId.isEmpty()) {
            sessionStore.resumeState().observeTerminal(observedTerminalId);
        }

        stateMachine = new GhoDexGatewayClientStateMachine(
            new GhoDexGatewayTcpTransport(host, port),
            sessionStore,
            terminalIndexStore
        );
        stateMachine.addStateListener(uiStore);
        stateMachine.addStateListener((ignoredSession, ignoredIndex) -> {
            persistSession();
            runOnUiThread(this::renderSnapshot);
        });
    }

    private void runAction(String label, BackgroundAction action) {
        executor.execute(() -> {
            try {
                setStatus(label + "...");
                action.run();
                persistSession();
                setStatus(capitalize(label) + " ok");
            } catch (Exception e) {
                setStatus(capitalize(label) + " failed: " + e.getMessage());
            }
        });
    }

    private void persistSession() {
        if (sessionStore == null) {
            return;
        }

        preferencesStore.saveSession(
            sessionStore.getPairingCode(),
            sessionStore.getAuthToken(),
            sessionStore.getTokenId(),
            sessionStore.getScopes(),
            currentObservedTerminalId()
        );
    }

    private void renderSnapshot() {
        if (uiStore == null) {
            stateView.setText("No state machine");
            return;
        }

        GhoDexGatewayUiSnapshot snapshot = uiStore.snapshot();
        StringBuilder out = new StringBuilder();
        out.append("host=").append(currentHost).append(':').append(currentPort).append('\n');
        out.append("pairingCode=").append(nullToDash(snapshot.getPairingCode())).append('\n');
        out.append("authTokenPresent=").append(snapshot.isAuthTokenPresent()).append('\n');
        out.append("tokenId=").append(nullToDash(snapshot.getTokenId())).append('\n');
        out.append("protocolVersion=").append(nullToDash(snapshot.getProtocolVersion())).append('\n');
        out.append("subscriptionOpen=").append(snapshot.isSubscriptionOpen()).append('\n');
        out.append("snapshotResyncRequired=").append(snapshot.isSnapshotResyncRequired()).append('\n');
        out.append("scopes=").append(snapshot.getScopes()).append('\n');
        out.append("observedTerminalIds=").append(snapshot.getObservedTerminalIds()).append('\n');
        out.append('\n').append("terminals").append('\n');

        for (GhoDexGatewayUiSnapshot.TerminalRow terminal : snapshot.getTerminals()) {
            out.append("- id=").append(terminal.getTerminalId()).append('\n');
            out.append("  title=").append(nullToDash(terminal.getTitle())).append('\n');
            out.append("  cwd=").append(nullToDash(terminal.getWorkingDirectory())).append('\n');
            out.append("  generation=").append(terminal.getGeneration()).append('\n');
            out.append("  focused=").append(terminal.isFocused()).append('\n');
            out.append("  visible=").append(terminal.isVisible()).append('\n');
            out.append("  lastEvent=").append(nullToDash(terminal.getLastEvent())).append('\n');
        }

        stateView.setText(out.toString());
        autofillTerminalIdIfNeeded();
        authTokenInput.setText(snapshot.isAuthTokenPresent() ? nullToEmpty(sessionStore.getAuthToken()) : "");
        pairingCodeInput.setText(nullToEmpty(snapshot.getPairingCode()));
    }

    private void autofillTerminalIdIfNeeded() {
        if (uiStore == null || !terminalIdInput.getText().toString().trim().isEmpty()) {
            return;
        }
        List<GhoDexGatewayUiSnapshot.TerminalRow> terminals = uiStore.snapshot().getTerminals();
        if (!terminals.isEmpty()) {
            terminalIdInput.setText(terminals.get(0).getTerminalId());
        }
    }

    private String nextRequestId(String prefix) {
        return String.format(Locale.US, "%s-%d", prefix, requestCounter.getAndIncrement());
    }

    private void captureConnectionInputs() {
        String host = hostInput.getText().toString().trim();
        if (host.isEmpty()) {
            host = "127.0.0.1";
            hostInput.setText(host);
        }

        int port;
        try {
            port = Integer.parseInt(portInput.getText().toString().trim());
        } catch (NumberFormatException e) {
            port = 45777;
            portInput.setText(Integer.toString(port));
        }

        preferencesStore.saveConnection(host, port);
        preferencesStore.saveSession(
            pairingCodeInput.getText().toString().trim(),
            authTokenInput.getText().toString().trim(),
            sessionStore == null ? null : sessionStore.getTokenId(),
            sessionStore == null ? List.of() : sessionStore.getScopes(),
            terminalIdInput.getText().toString().trim()
        );
    }

    private void setStatus(String message) {
        runOnUiThread(() -> statusView.setText("Status: " + message));
    }

    private TextView addLabel(LinearLayout root, String text) {
        TextView view = new TextView(this);
        view.setText(text);
        root.addView(view);
        return view;
    }

    private EditText addEditText(LinearLayout root, String hint) {
        EditText editText = new EditText(this);
        editText.setHint(hint);
        root.addView(editText);
        return editText;
    }

    private EditText addNumericEditText(LinearLayout root, String hint) {
        EditText editText = addEditText(root, hint);
        editText.setInputType(InputType.TYPE_CLASS_NUMBER);
        return editText;
    }

    private void addButton(LinearLayout root, String label, View.OnClickListener listener) {
        Button button = new Button(this);
        button.setText(label);
        button.setOnClickListener(listener);
        root.addView(button);
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private static String nullToDash(String value) {
        return value == null || value.isBlank() ? "-" : value;
    }

    private static String nullToEmpty(String value) {
        return value == null ? "" : value;
    }

    private String currentObservedTerminalId() {
        if (sessionStore == null || sessionStore.resumeState().observedTerminalIds().isEmpty()) {
            return null;
        }
        return sessionStore.resumeState().observedTerminalIds().iterator().next();
    }

    private static void requireNonEmpty(String value, String message) {
        if (value == null || value.isBlank()) {
            throw new IllegalStateException(message);
        }
    }

    private static String capitalize(String value) {
        if (value == null || value.isEmpty()) {
            return "";
        }
        return Character.toUpperCase(value.charAt(0)) + value.substring(1);
    }

    @FunctionalInterface
    private interface BackgroundAction {
        void run() throws Exception;
    }
}
