# GhoDex Relay Desktop-ID Routing

This document defines the required server-side routing model when multiple desktop GhoDex instances share one public relay endpoint (for example `wss://serverleon.leonai.top/ghodex/ws`).

## Why This Is Required

Mobile now connects relay sockets with `desktop_id` in the websocket URL query:

- `wss://serverleon.leonai.top/ghodex/ws?desktop_id=<desktop-id>`

If the relay server still forwards all requests to a single static upstream, multi-instance routing will fail with:

- `unable to open websocket ...`
- token/authorization mismatch against a different desktop instance
- intermittent `gateway authorization expired` after scan/rebind

## Target Topology

1. Public ingress: one endpoint path `/ghodex/ws`.
2. Server-side router: choose upstream by `$arg_desktop_id`.
3. Upstreams: each desktop instance is exposed to the server as a unique local target (for example distinct reverse-tunnel ports).

## Nginx Reference Configuration

```nginx
# /etc/nginx/conf.d/ghodex-relay.conf

map $arg_desktop_id $ghodex_upstream {
    default "";
    desktop_a http://127.0.0.1:29527;
    desktop_b http://127.0.0.1:39527;
    desktop_c http://127.0.0.1:49527;
}

server {
    listen 443 ssl http2;
    server_name serverleon.leonai.top;

    ssl_certificate     /etc/letsencrypt/live/serverleon.leonai.top/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/serverleon.leonai.top/privkey.pem;

    location = /ghodex/ws {
        if ($ghodex_upstream = "") {
            return 404;
        }

        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;

        proxy_pass $ghodex_upstream;
    }
}
```

## Desktop Configuration Contract

All desktop instances can publish the same `public_endpoint`:

- `wss://serverleon.leonai.top/ghodex/ws`

Routing isolation must come from each desktop's stable `desktop_id`, not from endpoint path differences.

## Single-Owner Gateway On One Device (New Default)

When multiple GhoDex instances run on the same machine:

1. The first instance keeps the configured gateway port (for example `9527`).
2. Later instances detect `EADDRINUSE`, probe that port for `gateway.instance.ping`, and treat it as the owner gateway if the probe succeeds.
3. Each later instance opens an internal local listener on an ephemeral port and registers a route into the owner gateway via:
   - `gateway.desktop.register`
   - payload: `desktop_id`, `desktop_label`, `upstream_host`, `upstream_port`
4. The owner gateway routes by `desktop_id`:
   - websocket path query `?desktop_id=...` is routed at handshake time,
   - TCP/JSON requests with `desktop_id` are proxied to the registered upstream.

Result: externally only one gateway entry is required per device, while mobile can still reach all local desktop instances by `desktop_id`.

## Route Safety and Stability Rules

The owner gateway now enforces the following route-hardening behavior:

1. Passive route registration must target a loopback upstream (`127.0.0.1` / `localhost` / `::1`).
2. During `gateway.desktop.register`, owner probes `upstream_host:upstream_port` with `gateway.instance.ping` and requires the upstream-reported `desktop_id` to match the registration `desktop_id`.
3. If owner cannot proxy to a registered upstream (`desktop_id` target down/unreachable), owner evicts that route immediately and returns `desktop_route_unreachable` to the caller.
4. WebSocket desktop handshake proxy no longer has a fixed 600s hard timeout; proxy lifetime now follows real socket lifecycle (close/error driven), improving SSH-like long-session stability.

## Acceptance Checklist

1. Each running desktop instance has a distinct `desktop_id` in pairing QR summary.
2. Relay ingress returns `404` when `desktop_id` is absent/unknown.
3. Relay ingress upgrades websocket and reaches expected upstream when `desktop_id` exists.
4. Scanning desktop A QR never binds to desktop B terminal list.
5. Opening multiple desktop instances no longer causes cross-instance authorization mismatch.

## Quick Validation Commands

1. Verify nginx syntax and reload:
```bash
sudo nginx -t && sudo systemctl reload nginx
```

2. Check unknown desktop_id returns 404:
```bash
curl -i "https://serverleon.leonai.top/ghodex/ws?desktop_id=unknown"
```

3. Check websocket upgrade path is reachable (expect `101` when upstream is alive):
```bash
printf 'GET /ghodex/ws?desktop_id=desktop_a HTTP/1.1\r\nHost: serverleon.leonai.top\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGVzdC13ZWJzb2NrZXQta2V5\r\nSec-WebSocket-Version: 13\r\n\r\n' \
| openssl s_client -quiet -connect serverleon.leonai.top:443 -servername serverleon.leonai.top
```

## Operational Notes

- Do not route `/ghodex/ws` to a fixed single upstream in multi-instance mode.
- Keep the routing table authoritative and audited: `desktop_id -> upstream`.
- If desktop process restarts and reverse-tunnel target changes, update mapping before mobile reconnect tests.
