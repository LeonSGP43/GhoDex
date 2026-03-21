package com.leongong.ghodex.remote;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

public final class GhoDexGatewaySessionStore {
    private final GhoDexGatewayResumeState resumeState = new GhoDexGatewayResumeState();
    private String pairingCode;
    private String tokenId;
    private String protocolVersion;
    private List<String> scopes = List.of();
    private boolean subscriptionOpen;
    private boolean snapshotResyncRequired;

    public GhoDexGatewayResumeState resumeState() {
        return resumeState;
    }

    public void recordPairingCode(String pairingCode) {
        this.pairingCode = pairingCode;
    }

    public String getPairingCode() {
        return pairingCode;
    }

    public void activateToken(String authToken, String tokenId, List<String> scopes) {
        resumeState.setAuthToken(authToken);
        this.tokenId = tokenId;
        this.scopes = Collections.unmodifiableList(new ArrayList<>(scopes));
    }

    public String getAuthToken() {
        return resumeState.getAuthToken();
    }

    public String getTokenId() {
        return tokenId;
    }

    public List<String> getScopes() {
        return scopes;
    }

    public void setProtocolVersion(String protocolVersion) {
        this.protocolVersion = protocolVersion;
    }

    public String getProtocolVersion() {
        return protocolVersion;
    }

    public void setSubscriptionOpen(boolean subscriptionOpen) {
        this.subscriptionOpen = subscriptionOpen;
    }

    public boolean isSubscriptionOpen() {
        return subscriptionOpen;
    }

    public void requireSnapshotResync() {
        snapshotResyncRequired = true;
    }

    public void clearSnapshotResyncRequirement() {
        snapshotResyncRequired = false;
    }

    public boolean isSnapshotResyncRequired() {
        return snapshotResyncRequired;
    }
}
