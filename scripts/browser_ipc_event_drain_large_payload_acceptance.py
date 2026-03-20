#!/usr/bin/env python3

"""
True large-payload Browser IPC event-drain acceptance harness.

This script stresses the Browser IPC response path using real
`pageInspectionSnapshot` event payloads instead of synthetic `newTab` result
blobs. It assumes a Browser-control-capable GhoDex instance is already running
and exposing `browser-control.sock`, ideally with CEF enabled so the
page-inspection events exist.

The harness:
1. Hosts a local small page and a large inspection page.
2. Opens a Browser tab to the small page and waits for `bridgeReady`.
3. Creates multiple slow-reader subscriptions for `pageInspectionSnapshot`.
4. Loads the large page and waits for one control subscription to observe a
   successful snapshot with non-empty `snapshotJSON`.
5. Sends unread `drainEvents` requests for the slow subscriptions so the IPC
   service must buffer real large event-drain responses.
6. Measures whether concurrent fast `listTabs` requests remain responsive.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import http.server
import json
import os
import socket
import socketserver
import statistics
import threading
import time
import uuid
from contextlib import contextmanager
from pathlib import Path


def default_socket_path() -> str:
    home = Path.home()
    return str(home / "Library" / "Application Support" / "GhoDex" / "browser-control.sock")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Stress Browser IPC with unread large pageInspectionSnapshot drain responses."
    )
    parser.add_argument("--socket", default=default_socket_path(), help="Path to browser-control.sock")
    parser.add_argument("--fast-count", type=int, default=8, help="Concurrent fast listTabs requests")
    parser.add_argument(
        "--slow-subscriptions",
        type=int,
        default=6,
        help="Number of unread pageInspectionSnapshot drain responses to queue",
    )
    parser.add_argument(
        "--row-count",
        type=int,
        default=1200,
        help="How many large DOM rows to render into the inspection page",
    )
    parser.add_argument(
        "--row-bytes",
        type=int,
        default=400,
        help="How many repeated payload characters each DOM row contains",
    )
    parser.add_argument(
        "--snapshot-timeout-ms",
        type=int,
        default=45000,
        help="How long to wait for a successful pageInspectionSnapshot event",
    )
    parser.add_argument(
        "--settle-ms",
        type=int,
        default=750,
        help="How long to wait after queuing unread drain responses before the fast burst",
    )
    parser.add_argument(
        "--max-fast-latency-ms",
        type=float,
        default=1000.0,
        help="Acceptance threshold for the slowest fast listTabs request",
    )
    parser.add_argument(
        "--output",
        default="/tmp/ghodex-browser-ipc-event-drain-large-payload-acceptance.json",
        help="Where to write the JSON report",
    )
    return parser.parse_args()


def recv_line(sock: socket.socket) -> str:
    data = b""
    while b"\n" not in data:
        chunk = sock.recv(65536)
        if not chunk:
            break
        data += chunk
    if not data:
        raise RuntimeError("socket closed before a response line was received")
    return data.decode().strip()


def send_request(
    socket_path: str,
    command: str,
    *,
    browser_tab_id: str | None = None,
    payload: dict[str, str] | None = None,
    timeout: float = 10.0,
) -> dict:
    body = {
        "id": str(uuid.uuid4()),
        "version": "browser.tab.v1",
        "command": command,
        "payload": payload or {},
    }
    if browser_tab_id is not None:
        body["browserTabID"] = browser_tab_id

    started = time.perf_counter()
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(timeout)
    client.connect(socket_path)
    client.sendall((json.dumps(body) + "\n").encode())
    line = recv_line(client)
    client.close()
    elapsed_ms = round((time.perf_counter() - started) * 1000, 2)
    response = json.loads(line)
    return {"elapsed_ms": elapsed_ms, "response": response, "request": body}


def run_listtabs_burst(socket_path: str, count: int) -> dict:
    started = time.perf_counter()
    with concurrent.futures.ThreadPoolExecutor(max_workers=count) as executor:
        results = list(executor.map(lambda _: send_request(socket_path, "listTabs"), range(count)))

    latencies = [item["elapsed_ms"] for item in results]
    return {
        "count": count,
        "total_ms": round((time.perf_counter() - started) * 1000, 2),
        "latency_ms": latencies,
        "max_latency_ms": max(latencies),
        "median_latency_ms": round(statistics.median(latencies), 2),
        "all_ok": all(item["response"].get("ok") is True for item in results),
    }


@contextmanager
def local_page_server(row_count: int, row_bytes: int):
    webroot = Path(os.path.realpath(Path("/tmp").joinpath(f"ghodex-browser-web-{uuid.uuid4().hex}")))
    webroot.mkdir(parents=True, exist_ok=True)

    small_html = "<html><body><h1>small</h1></body></html>"
    row_payload = "x" * row_bytes
    large_html = "<html><body>" + "".join(
        f'<div class="row" data-i="{index}">row {index} {row_payload}</div>'
        for index in range(row_count)
    ) + "</body></html>"

    (webroot / "small.html").write_text(small_html, encoding="utf-8")
    (webroot / "large.html").write_text(large_html, encoding="utf-8")

    class QuietHandler(http.server.SimpleHTTPRequestHandler):
        def log_message(self, format: str, *args) -> None:  # noqa: A003
            return

    class ThreadedTCPServer(socketserver.ThreadingTCPServer):
        allow_reuse_address = True

    handler = lambda *args, **kwargs: QuietHandler(*args, directory=str(webroot), **kwargs)
    server = ThreadedTCPServer(("127.0.0.1", 0), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield {
            "small_url": f"http://127.0.0.1:{server.server_address[1]}/small.html",
            "large_url": f"http://127.0.0.1:{server.server_address[1]}/large.html",
            "webroot": str(webroot),
        }
    finally:
        server.shutdown()
        server.server_close()


def extract_result_json(response: dict) -> dict:
    if response.get("ok") is not True:
        raise RuntimeError(f"request failed: {json.dumps(response, sort_keys=True)}")
    raw = response.get("resultJSON")
    if not isinstance(raw, str):
        raise RuntimeError(f"missing resultJSON in response: {json.dumps(response, sort_keys=True)}")
    return json.loads(raw)


def wait_for_bridge_ready(socket_path: str, subscription_id: str, timeout_ms: int) -> dict:
    deadline = time.monotonic() + (timeout_ms / 1000.0)
    observed = []
    while time.monotonic() < deadline:
        drain = send_request(
            socket_path,
            "drainEvents",
            payload={"subscriptionID": subscription_id, "limit": "128"},
        )
        result = extract_result_json(drain["response"])
        events = result["events"]
        observed.extend(events)
        if any(event["kind"] == "bridgeReady" for event in events):
            return {"events": observed, "result": result}
        time.sleep(0.25)
    raise RuntimeError("Timed out waiting for a bridgeReady event")


def wait_for_successful_snapshot(socket_path: str, subscription_id: str, timeout_ms: int) -> dict:
    deadline = time.monotonic() + (timeout_ms / 1000.0)
    observed = []
    while time.monotonic() < deadline:
        drain = send_request(
            socket_path,
            "drainEvents",
            payload={"subscriptionID": subscription_id, "limit": "256"},
            timeout=20.0,
        )
        result = extract_result_json(drain["response"])
        events = result["events"]
        observed.extend(events)
        for event in events:
            payload = event.get("payload", {})
            if (
                event.get("kind") == "pageInspectionSnapshot"
                and payload.get("ok") == "true"
                and payload.get("snapshotJSON")
            ):
                return {"event": event, "events": observed, "result": result}
        time.sleep(0.25)
    raise RuntimeError("Timed out waiting for a successful pageInspectionSnapshot event")


def open_unread_drain_client(socket_path: str, subscription_ids: list[str]) -> tuple[socket.socket, dict]:
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(5.0)
    client.connect(socket_path)

    request_ids = []
    for subscription_id in subscription_ids:
        request_id = str(uuid.uuid4())
        request_ids.append(request_id)
        body = {
            "id": request_id,
            "version": "browser.tab.v1",
            "command": "drainEvents",
            "payload": {
                "subscriptionID": subscription_id,
                "limit": "256",
            },
        }
        client.sendall((json.dumps(body) + "\n").encode())

    metadata = {
        "command": "drainEvents",
        "request_count": len(subscription_ids),
        "subscription_ids": subscription_ids,
        "request_ids": request_ids,
    }
    return client, metadata


def inspect_slow_reader(client: socket.socket) -> dict:
    status: dict[str, object] = {}
    try:
        client.settimeout(1.0)
        chunk = client.recv(4096)
        if chunk == b"":
            status["state"] = "closed"
        else:
            status["state"] = "readable"
            status["bytes_sampled"] = len(chunk)
            status["first_byte"] = chunk[:1].decode(errors="replace")
    except socket.timeout:
        status["state"] = "timeout"
    except OSError as exc:
        status["state"] = "socket_error"
        status["error"] = str(exc)
    finally:
        try:
            client.close()
        except OSError:
            pass
    return status


def main() -> int:
    args = parse_args()
    socket_path = os.path.expanduser(args.socket)
    if not os.path.exists(socket_path):
        raise SystemExit(f"Socket does not exist: {socket_path}")

    baseline = run_listtabs_burst(socket_path, args.fast_count)

    with local_page_server(args.row_count, args.row_bytes) as server_info:
        new_tab = send_request(socket_path, "newTab", payload={"url": server_info["small_url"]})
        tab_summary = extract_result_json(new_tab["response"])
        browser_tab_id = tab_summary["id"]

        control_subscription = extract_result_json(
            send_request(
                socket_path,
                "subscribeEvents",
                browser_tab_id=browser_tab_id,
                payload={
                    "kindsJSON": json.dumps(
                        ["bridgeReady", "navigationStateChanged", "networkRequestFinished", "pageInspectionSnapshot"]
                    )
                },
            )["response"]
        )
        control_subscription_id = control_subscription["subscriptionID"]

        slow_subscription_ids = []
        for _ in range(args.slow_subscriptions):
            subscription = extract_result_json(
                send_request(
                    socket_path,
                    "subscribeEvents",
                    browser_tab_id=browser_tab_id,
                    payload={
                        "kindsJSON": json.dumps(
                            ["navigationStateChanged", "networkRequestFinished", "pageInspectionSnapshot"]
                        )
                    },
                )["response"]
            )
            slow_subscription_ids.append(subscription["subscriptionID"])

        bridge_ready = wait_for_bridge_ready(socket_path, control_subscription_id, args.snapshot_timeout_ms)

        load_result = send_request(
            socket_path,
            "loadURL",
            browser_tab_id=browser_tab_id,
            payload={"url": server_info["large_url"]},
            timeout=20.0,
        )
        if load_result["response"].get("ok") is not True:
            raise RuntimeError(f"loadURL failed: {json.dumps(load_result['response'], sort_keys=True)}")

        successful_snapshot = wait_for_successful_snapshot(
            socket_path,
            control_subscription_id,
            args.snapshot_timeout_ms,
        )
        snapshot_event = successful_snapshot["event"]
        snapshot_payload = snapshot_event["payload"]
        snapshot_json = snapshot_payload["snapshotJSON"]

        slow_client, slow_metadata = open_unread_drain_client(socket_path, slow_subscription_ids)
        time.sleep(args.settle_ms / 1000.0)

        under_pressure = run_listtabs_burst(socket_path, args.fast_count)
        slow_status = inspect_slow_reader(slow_client)
        post_check = send_request(socket_path, "listTabs")

        result = {
            "socket_path": socket_path,
            "browser_tab_id": browser_tab_id,
            "baseline": baseline,
            "bridge_ready": {
                "observed_event_count": len(bridge_ready["events"]),
                "last_cursor": bridge_ready["result"]["nextCursor"],
            },
            "successful_snapshot": {
                "trigger_kind": snapshot_payload.get("triggerKind"),
                "snapshot_json_bytes": len(snapshot_json.encode("utf-8")),
                "snapshot_json_chars": len(snapshot_json),
                "page_id": snapshot_payload.get("pageID"),
                "document_revision": snapshot_payload.get("documentRevision"),
            },
            "slow_client": {
                **slow_metadata,
                "status": slow_status,
            },
            "under_pressure": under_pressure,
            "post_check": post_check,
            "acceptance": {
                "baseline_all_ok": baseline["all_ok"],
                "successful_snapshot_found": bool(snapshot_json),
                "snapshot_is_large": len(snapshot_json.encode("utf-8")) > 50000,
                "under_pressure_all_ok": under_pressure["all_ok"],
                "under_pressure_max_lt_threshold": under_pressure["max_latency_ms"] < args.max_fast_latency_ms,
                "post_check_ok": post_check["response"].get("ok") is True,
            },
            "notes": [
                "The unread responses are real drainEvents payloads carrying pageInspectionSnapshot event envelopes.",
                "This path exercises the true buffered event-drain response flow instead of synthetic newTab result bodies.",
                "A Browser instance with working pageInspectionSnapshot events is required; the intended target is a CEF-enabled app build.",
            ],
        }

    output_path = Path(args.output)
    output_path.write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
