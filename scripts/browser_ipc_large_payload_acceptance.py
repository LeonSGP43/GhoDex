#!/usr/bin/env python3

"""
Large-payload Browser IPC acceptance harness.

This script exercises the Browser IPC response path with one intentionally slow
reader connection and a burst of fast clients. The slow reader uses large
`newTab` responses because that is the most deterministic externally reachable
large-payload path today. Those responses still travel through the same
newline-delimited IPC framing, per-connection buffering, and backpressure logic
used by large Browser inspection and event payloads.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import os
import socket
import statistics
import time
import uuid
from pathlib import Path


def default_socket_path() -> str:
    home = Path.home()
    return str(home / "Library" / "Application Support" / "GhoDex" / "browser-control.sock")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Stress the Browser IPC service with large unread responses and concurrent fast requests."
    )
    parser.add_argument("--socket", default=default_socket_path(), help="Path to browser-control.sock")
    parser.add_argument("--fast-count", type=int, default=8, help="Number of concurrent fast listTabs requests")
    parser.add_argument("--slow-count", type=int, default=12, help="Number of unread large-response requests")
    parser.add_argument(
        "--payload-bytes",
        type=int,
        default=150000,
        help="Number of HTML payload bytes embedded in each large data URL request",
    )
    parser.add_argument(
        "--settle-ms",
        type=int,
        default=750,
        help="How long to wait after queuing slow requests before running the fast burst",
    )
    parser.add_argument(
        "--max-fast-latency-ms",
        type=float,
        default=1000.0,
        help="Acceptance threshold for the slowest fast request",
    )
    parser.add_argument(
        "--output",
        default="/tmp/ghodex-browser-ipc-large-payload-acceptance.json",
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


def send_request(socket_path: str, command: str, payload: dict[str, str] | None = None, timeout: float = 5.0) -> dict:
    body = {
        "id": str(uuid.uuid4()),
        "version": "browser.tab.v1",
        "command": command,
        "payload": payload or {},
    }
    started = time.perf_counter()
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(timeout)
    client.connect(socket_path)
    client.sendall((json.dumps(body) + "\n").encode())
    line = recv_line(client)
    client.close()
    elapsed_ms = round((time.perf_counter() - started) * 1000, 2)
    return {"elapsed_ms": elapsed_ms, "response": json.loads(line)}


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


def open_slow_reader(socket_path: str, slow_count: int, payload_bytes: int) -> tuple[socket.socket, dict]:
    payload = "data:text/html," + ("x" * payload_bytes)
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(5.0)
    client.connect(socket_path)

    request_ids: list[str] = []
    for _ in range(slow_count):
        request_id = str(uuid.uuid4())
        request_ids.append(request_id)
        body = {
            "id": request_id,
            "version": "browser.tab.v1",
            "command": "newTab",
            "payload": {"url": payload},
        }
        client.sendall((json.dumps(body) + "\n").encode())

    metadata = {
        "command": "newTab",
        "request_count": slow_count,
        "payload_chars": len(payload),
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

    slow_client, slow_metadata = open_slow_reader(socket_path, args.slow_count, args.payload_bytes)
    time.sleep(args.settle_ms / 1000.0)

    under_pressure = run_listtabs_burst(socket_path, args.fast_count)
    slow_status = inspect_slow_reader(slow_client)
    post_check = send_request(socket_path, "listTabs")

    result = {
        "socket_path": socket_path,
        "baseline": baseline,
        "under_pressure": under_pressure,
        "slow_client": {
            **slow_metadata,
            "status": slow_status,
        },
        "post_check": post_check,
        "acceptance": {
            "baseline_all_ok": baseline["all_ok"],
            "under_pressure_all_ok": under_pressure["all_ok"],
            "under_pressure_max_lt_threshold": under_pressure["max_latency_ms"] < args.max_fast_latency_ms,
            "post_check_ok": post_check["response"].get("ok") is True,
        },
        "notes": [
            "Large newTab data URLs are used as the deterministic large-response source.",
            "This still exercises the same per-connection response buffering and backpressure path used by large inspection and event payloads.",
        ],
    }

    output_path = Path(args.output)
    output_path.write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
