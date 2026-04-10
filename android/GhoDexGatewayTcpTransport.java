package com.leongong.ghodex.remote;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.charset.StandardCharsets;

public final class GhoDexGatewayTcpTransport implements GhoDexGatewayTransport {
    private final String host;
    private final int port;
    private final int connectTimeoutMs;
    private final int readTimeoutMs;

    public GhoDexGatewayTcpTransport(String host, int port) {
        this(host, port, 3_000, 5_000);
    }

    public GhoDexGatewayTcpTransport(String host, int port, int connectTimeoutMs, int readTimeoutMs) {
        this.host = host;
        this.port = port;
        this.connectTimeoutMs = connectTimeoutMs;
        this.readTimeoutMs = readTimeoutMs;
    }

    @Override
    public GhoDexGatewayEnvelope send(GhoDexGatewayRequest request) {
        try (Socket socket = openSocket()) {
            writeRequest(socket, request);
            String response = readAll(socket.getInputStream());
            return GhoDexGatewayJsonCodec.decodeEnvelope(response);
        } catch (IOException e) {
            throw new IllegalStateException("gateway send failed", e);
        }
    }

    private Socket openSocket() throws IOException {
        Socket socket = new Socket();
        socket.connect(new InetSocketAddress(host, port), connectTimeoutMs);
        socket.setSoTimeout(readTimeoutMs);
        return socket;
    }

    private static void writeRequest(Socket socket, GhoDexGatewayRequest request) throws IOException {
        OutputStream outputStream = socket.getOutputStream();
        outputStream.write(request.toJson().getBytes(StandardCharsets.UTF_8));
        outputStream.flush();
        socket.shutdownOutput();
    }

    private static String readAll(InputStream inputStream) throws IOException {
        ByteArrayOutputStream buffer = new ByteArrayOutputStream();
        inputStream.transferTo(buffer);
        return buffer.toString(StandardCharsets.UTF_8);
    }
}
