public interface GhoDexGatewayTransport {
    GhoDexGatewayEnvelope send(GhoDexGatewayRequest request);

    Subscription openSubscription(GhoDexGatewayRequest request, EventSink sink);

    interface EventSink {
        void onEnvelope(GhoDexGatewayEnvelope envelope);
    }

    interface Subscription extends AutoCloseable {
        @Override
        void close();
    }
}
