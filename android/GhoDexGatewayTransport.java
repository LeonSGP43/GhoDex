package com.leongong.ghodex.remote;

public interface GhoDexGatewayTransport {
    GhoDexGatewayEnvelope send(GhoDexGatewayRequest request);
}
