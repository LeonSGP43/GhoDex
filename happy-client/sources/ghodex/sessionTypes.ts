export type StoredTransportMode = 'lan' | 'relay';

export interface StoredSession {
    deviceId: string;
    deviceLabel: string;
    desktopId: string;
    desktopLabel: string;
    preferredDesktopId: string;
    transportMode: StoredTransportMode;
    publicEndpoint: string;
    transportSharedSecret: string;
    host: string;
    port: number;
    pairingCode: string;
    authToken: string;
    tokenId: string;
    scopes: string[];
    requestedScopes: string[];
    liveUpdatesEnabled: boolean;
    pollIntervalMs: number;
}
