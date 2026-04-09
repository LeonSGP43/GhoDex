#!/usr/bin/env python3

"""
Control Harness gateway transport live acceptance harness.

This harness launches an isolated GhoDex.app and proves the event and gateway
transport layers against a live app instance:

- local Unix-socket `events.subscribe` streams replay + live events
- gateway TCP handshake succeeds and pairing exchanges an observe token
- gateway TCP `terminal.snapshot.v2` / `terminal.semantic.v2` work with auth
- gateway TCP `events.subscribe` streams replay + live events
- gateway WebSocket handshake succeeds
- gateway WebSocket `terminal.snapshot.v2` / `terminal.semantic.v2` work with auth
- gateway WebSocket `events.subscribe` streams replay + live events
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import re
import socket
import struct
import subprocess
import time
import uuid
from pathlib import Path
from typing import Callable


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = "/tmp/ghx-control-harness-gateway-transport-live-acceptance.json"
HARNESS_SOCKET_RE = re.compile(r"(?P<path>/Users/.*/ControlHarness/harness\.sock)$")
LISTEN_PORT_RE = re.compile(r"TCP .*:(?P<port>\d+) \(LISTEN\)$")


class SocketLineReader:
    def __init__(self, sock: socket.socket):
        self.sock = sock
        self.buffer = b""

    def read_line(self, *, timeout: float) -> str:
        deadline = time.monotonic() + timeout
        while True:
            if b"\n" in self.buffer:
                line, self.buffer = self.buffer.split(b"\n", 1)
                return line.decode().strip()

            remaining = max(0.05, deadline - time.monotonic())
            self.sock.settimeout(remaining)
            chunk = self.sock.recv(65536)
            if not chunk:
                if self.buffer:
                    line = self.buffer
                    self.buffer = b""
                    return line.decode().strip()
                raise RuntimeError("socket closed before a line was received")
            self.buffer += chunk

    def read_until_close(self, *, timeout: float) -> str:
        deadline = time.monotonic() + timeout
        chunks = [self.buffer] if self.buffer else []
        self.buffer = b""
        while True:
            remaining = max(0.05, deadline - time.monotonic())
            self.sock.settimeout(remaining)
            chunk = self.sock.recv(65536)
            if not chunk:
                data = b"".join(chunks)
                if not data:
                    raise RuntimeError("socket closed before a response body was received")
                return data.decode().strip()
            chunks.append(chunk)


class WebSocketConnection:
    def __init__(self, sock: socket.socket, *, initial_buffer: bytes = b""):
        self.sock = sock
        self.buffer = initial_buffer

    def send_text(self, payload: dict) -> None:
        body = json.dumps(payload).encode()
        self._send_frame(opcode=0x1, payload=body)

    def close(self) -> None:
        try:
            self._send_frame(opcode=0x8, payload=b"")
        except OSError:
            pass
        try:
            self.sock.close()
        except OSError:
            pass

    def read_json(self, *, timeout: float) -> dict:
        deadline = time.monotonic() + timeout
        while True:
            opcode, payload = self._read_frame(timeout=max(0.05, deadline - time.monotonic()))
            if opcode == 0x1:
                return json.loads(payload.decode())
            if opcode == 0x9:
                self._send_frame(opcode=0xA, payload=payload)
                continue
            if opcode == 0xA:
                continue
            if opcode == 0x8:
                raise RuntimeError("websocket closed before a JSON text frame was received")
            raise RuntimeError(f"unsupported websocket opcode: {opcode}")

    def _send_frame(self, *, opcode: int, payload: bytes) -> None:
        fin_opcode = 0x80 | (opcode & 0x0F)
        mask_key = os.urandom(4)
        length = len(payload)
        header = bytearray([fin_opcode])
        if length < 126:
            header.append(0x80 | length)
        elif length < (1 << 16):
            header.append(0x80 | 126)
            header.extend(struct.pack("!H", length))
        else:
            header.append(0x80 | 127)
            header.extend(struct.pack("!Q", length))
        masked = bytes(byte ^ mask_key[index % 4] for index, byte in enumerate(payload))
        self.sock.sendall(bytes(header) + mask_key + masked)

    def _read_exact(self, size: int, *, timeout: float) -> bytes:
        deadline = time.monotonic() + timeout
        while len(self.buffer) < size:
            remaining = max(0.05, deadline - time.monotonic())
            self.sock.settimeout(remaining)
            chunk = self.sock.recv(65536)
            if not chunk:
                raise RuntimeError("websocket closed unexpectedly")
            self.buffer += chunk
        data = self.buffer[:size]
        self.buffer = self.buffer[size:]
        return data

    def _read_frame(self, *, timeout: float) -> tuple[int, bytes]:
        header = self._read_exact(2, timeout=timeout)
        first, second = header[0], header[1]
        opcode = first & 0x0F
        masked = (second & 0x80) != 0
        length = second & 0x7F
        if length == 126:
            length = struct.unpack("!H", self._read_exact(2, timeout=timeout))[0]
        elif length == 127:
            length = struct.unpack("!Q", self._read_exact(8, timeout=timeout))[0]

        mask_key = self._read_exact(4, timeout=timeout) if masked else b""
        payload = self._read_exact(length, timeout=timeout) if length else b""
        if masked:
            payload = bytes(byte ^ mask_key[index % 4] for index, byte in enumerate(payload))
        return opcode, payload


def resolve_default_app() -> Path:
    candidates = [
        REPO_ROOT / "macos" / "build" / "ReleaseLocal" / "GhoDex.app",
        REPO_ROOT / "macos" / "build" / "Debug" / "GhoDex.app",
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    raise SystemExit(
        "No built GhoDex.app found under macos/build/{ReleaseLocal,Debug}. "
        "Pass --app=/path/to/GhoDex.app."
    )


def resolve_default_runtime_root() -> Path:
    candidates = [
        REPO_ROOT / "macos" / "build" / "cef-runtime" / "current",
        Path.home() / "Library" / "Application Support" / "GhoDex" / "CEF" / "current",
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate

    home_cef_root = Path.home() / "Library" / "Application Support" / "GhoDex" / "CEF"
    if home_cef_root.exists():
        matches = sorted(home_cef_root.glob("cef_binary_*"))
        if matches:
            return matches[-1]

    raise SystemExit(
        "No default CEF runtime root found. Pass --runtime-root=/path/to/runtime."
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Prove Control Harness events and gateway transports against a live GhoDex app."
    )
    parser.add_argument("--app", default=None, help="Path to the GhoDex.app bundle to launch.")
    parser.add_argument(
        "--runtime-root",
        default=None,
        help="CEF runtime root passed through GHODEX_CEF_ROOT.",
    )
    parser.add_argument(
        "--startup-timeout-ms",
        type=int,
        default=30000,
        help="Timeout budget for app launch and socket/listener discovery.",
    )
    parser.add_argument(
        "--request-timeout",
        type=float,
        default=10.0,
        help="Per-request timeout in seconds.",
    )
    parser.add_argument(
        "--stream-timeout-ms",
        type=int,
        default=10000,
        help="Timeout budget for replay/live event streams.",
    )
    parser.add_argument(
        "--output",
        default=DEFAULT_OUTPUT,
        help="Where to write the JSON artifact.",
    )
    return parser.parse_args()


def terminate_process(proc: subprocess.Popen[str], timeout: float = 15.0) -> None:
    if proc.poll() is not None:
        return
    proc.terminate()
    deadline = time.time() + (timeout / 2)
    while time.time() < deadline:
        if proc.poll() is not None:
            return
        time.sleep(0.25)

    proc.kill()
    deadline = time.time() + (timeout / 2)
    while time.time() < deadline:
        if proc.poll() is not None:
            return
        time.sleep(0.25)

    raise RuntimeError(f"Process {proc.pid} did not exit in time")


def launch_app(
    app_bundle: Path,
    log_path: Path,
    *,
    runtime_root: Path,
    app_support_root: Path,
    home_dir: Path,
    config_path: Path,
) -> subprocess.Popen[str]:
    executable = app_bundle / "Contents" / "MacOS" / "GhoDex"
    if not executable.exists():
        raise RuntimeError(f"App executable does not exist: {executable}")

    env = os.environ.copy()
    env["GHODEX_CEF_ROOT"] = str(runtime_root)
    env["GHODEX_BROWSER_APP_SUPPORT_ROOT"] = str(app_support_root)
    env["GHOSTTY_CONFIG_PATH"] = str(config_path)
    env["HOME"] = str(home_dir)
    env["TMPDIR"] = str(home_dir / "tmp")
    env.pop("GHODEX_CEF_PROFILE_PATH", None)

    home_dir.mkdir(parents=True, exist_ok=True)
    (home_dir / "tmp").mkdir(parents=True, exist_ok=True)
    app_support_root.mkdir(parents=True, exist_ok=True)
    config_path.parent.mkdir(parents=True, exist_ok=True)
    config_path.write_text(
        "\n".join([
            "initial-window = true",
            "quit-after-last-window-closed = false",
            "",
        ]),
        encoding="utf-8",
    )

    log_path.write_text("", encoding="utf-8")
    with log_path.open("a", encoding="utf-8") as log_file:
        return subprocess.Popen(
            [str(executable), "-psn_0_0"],
            env=env,
            cwd=str(app_bundle.parent),
            stdout=log_file,
            stderr=subprocess.STDOUT,
            text=True,
        )


def wait_for_harness_socket(pid: int, *, timeout_ms: int) -> str:
    deadline = time.monotonic() + (timeout_ms / 1000.0)
    last_lsof = ""
    while time.monotonic() < deadline:
        completed = subprocess.run(
            ["lsof", "-Pan", "-p", str(pid)],
            capture_output=True,
            text=True,
            timeout=10.0,
            check=False,
        )
        last_lsof = completed.stdout
        for line in completed.stdout.splitlines():
            match = HARNESS_SOCKET_RE.search(line)
            if match:
                return match.group("path")
        time.sleep(0.25)

    raise RuntimeError(
        f"Timed out waiting for Control Harness socket for pid {pid}. "
        f"Last lsof sample: {last_lsof[-400:]}"
    )


def wait_for_gateway_port(pid: int, *, timeout_ms: int) -> int:
    deadline = time.monotonic() + (timeout_ms / 1000.0)
    last_lsof = ""
    while time.monotonic() < deadline:
        completed = subprocess.run(
            ["lsof", "-Pan", "-p", str(pid), "-iTCP", "-sTCP:LISTEN"],
            capture_output=True,
            text=True,
            timeout=10.0,
            check=False,
        )
        last_lsof = completed.stdout
        for line in completed.stdout.splitlines():
            match = LISTEN_PORT_RE.search(line)
            if match:
                return int(match.group("port"))
        time.sleep(0.25)

    raise RuntimeError(
        f"Timed out waiting for gateway TCP listener for pid {pid}. "
        f"Last lsof sample: {last_lsof[-400:]}"
    )


def connect_unix(socket_path: str, *, timeout: float) -> socket.socket:
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(timeout)
    client.connect(socket_path)
    return client


def connect_tcp(host: str, port: int, *, timeout: float) -> socket.socket:
    client = socket.create_connection((host, port), timeout=timeout)
    client.settimeout(timeout)
    return client


def send_single_request_unix(socket_path: str, body: dict, *, timeout: float) -> dict:
    client = connect_unix(socket_path, timeout=timeout)
    reader = SocketLineReader(client)
    client.sendall((json.dumps(body) + "\n").encode())
    client.shutdown(socket.SHUT_WR)
    response_text = reader.read_until_close(timeout=timeout)
    client.close()
    return json.loads(response_text)


def send_single_request_tcp(host: str, port: int, body: dict, *, timeout: float) -> dict:
    client = connect_tcp(host, port, timeout=timeout)
    reader = SocketLineReader(client)
    client.sendall(json.dumps(body).encode())
    client.shutdown(socket.SHUT_WR)
    response_text = reader.read_until_close(timeout=timeout)
    client.close()
    return json.loads(response_text)


def open_line_subscription_unix(
    socket_path: str,
    body: dict,
    *,
    timeout: float,
) -> tuple[socket.socket, SocketLineReader, dict]:
    client = connect_unix(socket_path, timeout=timeout)
    reader = SocketLineReader(client)
    client.sendall((json.dumps(body) + "\n").encode())
    client.shutdown(socket.SHUT_WR)
    ack = json.loads(reader.read_line(timeout=timeout))
    return client, reader, ack


def open_line_subscription_tcp(
    host: str,
    port: int,
    body: dict,
    *,
    timeout: float,
) -> tuple[socket.socket, SocketLineReader, dict]:
    client = connect_tcp(host, port, timeout=timeout)
    reader = SocketLineReader(client)
    client.sendall(json.dumps(body).encode())
    client.shutdown(socket.SHUT_WR)
    ack = json.loads(reader.read_line(timeout=timeout))
    return client, reader, ack


def read_http_headers(sock: socket.socket, *, timeout: float) -> tuple[str, bytes]:
    deadline = time.monotonic() + timeout
    buffer = b""
    marker = b"\r\n\r\n"
    while marker not in buffer:
        remaining = max(0.05, deadline - time.monotonic())
        sock.settimeout(remaining)
        chunk = sock.recv(65536)
        if not chunk:
            raise RuntimeError("socket closed before websocket handshake completed")
        buffer += chunk
    headers, remainder = buffer.split(marker, 1)
    return headers.decode(), remainder


def open_websocket(host: str, port: int, *, timeout: float) -> tuple[WebSocketConnection, dict]:
    client = connect_tcp(host, port, timeout=timeout)
    key = base64.b64encode(os.urandom(16)).decode()
    request = (
        f"GET /control-harness HTTP/1.1\r\n"
        f"Host: {host}:{port}\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        "Sec-WebSocket-Version: 13\r\n"
        "\r\n"
    ).encode()
    client.sendall(request)
    headers_text, remainder = read_http_headers(client, timeout=timeout)
    if "101 Switching Protocols" not in headers_text:
        raise RuntimeError(f"websocket handshake failed: {headers_text}")
    expected_accept = base64.b64encode(
        hashlib.sha1(f"{key}258EAFA5-E914-47DA-95CA-C5AB0DC85B11".encode()).digest()
    ).decode()
    if f"Sec-WebSocket-Accept: {expected_accept}" not in headers_text:
        raise RuntimeError(
            "websocket handshake returned an unexpected Sec-WebSocket-Accept header"
        )
    return WebSocketConnection(client, initial_buffer=remainder), {
        "status_line": headers_text.splitlines()[0],
        "expected_accept": expected_accept,
    }


def websocket_request(websocket: WebSocketConnection, body: dict, *, timeout: float) -> dict:
    websocket.send_text(body)
    return websocket.read_json(timeout=timeout)


def run_control_command(app_bundle: Path, socket_path: str, *control_args: str) -> dict:
    executable = app_bundle / "Contents" / "MacOS" / "GhoDex"
    completed = subprocess.run(
        [str(executable), "+control", *control_args, f"--socket={socket_path}"],
        capture_output=True,
        text=True,
        timeout=20.0,
        check=True,
    )
    return json.loads(completed.stdout)


def wait_for_primary_terminal(app_bundle: Path, socket_path: str, *, timeout_ms: int) -> tuple[str, dict]:
    deadline = time.monotonic() + (timeout_ms / 1000.0)
    last_snapshot: dict | None = None
    while time.monotonic() < deadline:
        snapshot = run_control_command(app_bundle, socket_path, "snapshot")
        last_snapshot = snapshot
        tabs = snapshot.get("result", {}).get("tabs") or []
        terminals = [terminal for tab in tabs for terminal in tab.get("terminals") or []]
        if terminals:
            return str(terminals[0]["terminal_id"]), snapshot
        time.sleep(0.25)

    raise RuntimeError(
        "Timed out waiting for a primary terminal. "
        f"Last snapshot: {json.dumps(last_snapshot or {}, sort_keys=True)}"
    )


def wait_for_write_settle(
    app_bundle: Path,
    socket_path: str,
    *,
    terminal_id: str,
    write_id: str,
    timeout_ms: int,
) -> dict:
    deadline = time.monotonic() + (timeout_ms / 1000.0)
    last_read: dict | None = None
    while time.monotonic() < deadline:
        read_result = run_control_command(
            app_bundle,
            socket_path,
            "read-terminal",
            f"--terminal-id={terminal_id}",
            "--scope=screen",
            "--mode=snapshot",
            "--max-lines=200",
            "--max-chars=24000",
            f"--read-after-write-id={write_id}",
        )
        last_read = read_result
        observed = read_result.get("result", {}).get("observed_write_id")
        if observed == write_id:
            return read_result
        time.sleep(0.25)

    raise RuntimeError(
        "Timed out waiting for terminal write settle. "
        f"Last read: {json.dumps(last_read or {}, sort_keys=True)}"
    )


def issue_run_command(
    app_bundle: Path,
    socket_path: str,
    *,
    terminal_id: str,
    marker: str,
    timeout_ms: int,
) -> dict:
    command = run_control_command(
        app_bundle,
        socket_path,
        "run-command",
        f"--terminal-id={terminal_id}",
        f"--command=printf {marker}\\n",
    )
    write_id = command["result"]["write_id"]
    settle = wait_for_write_settle(
        app_bundle,
        socket_path,
        terminal_id=terminal_id,
        write_id=write_id,
        timeout_ms=timeout_ms,
    )
    return {
        "command": command,
        "settle": settle,
        "request_id": command["request_id"],
        "sequence": int(command["result"]["sequence"]),
        "write_id": write_id,
        "marker": marker,
    }


def wait_for_event_line(
    reader: SocketLineReader,
    *,
    timeout_ms: int,
    predicate: Callable[[dict], bool],
) -> dict:
    deadline = time.monotonic() + (timeout_ms / 1000.0)
    observed: list[dict] = []
    while time.monotonic() < deadline:
        remaining = max(0.05, deadline - time.monotonic())
        try:
            record = json.loads(reader.read_line(timeout=remaining))
        except socket.timeout:
            continue
        observed.append(record)
        if predicate(record):
            matched = dict(record)
            matched["_observed_records"] = list(observed)
            return matched

    raise RuntimeError(
        "Timed out waiting for expected event line. "
        f"Observed {len(observed)} record(s): {json.dumps(observed[-3:], sort_keys=True)}"
    )


def wait_for_event_ws(
    websocket: WebSocketConnection,
    *,
    timeout_ms: int,
    predicate: Callable[[dict], bool],
) -> dict:
    deadline = time.monotonic() + (timeout_ms / 1000.0)
    observed: list[dict] = []
    while time.monotonic() < deadline:
        remaining = max(0.05, deadline - time.monotonic())
        record = websocket.read_json(timeout=remaining)
        observed.append(record)
        if predicate(record):
            matched = dict(record)
            matched["_observed_records"] = list(observed)
            return matched

    raise RuntimeError(
        "Timed out waiting for expected websocket event. "
        f"Observed {len(observed)} record(s): {json.dumps(observed[-3:], sort_keys=True)}"
    )


def issue_observe_token(host: str, port: int, *, timeout: float) -> dict:
    begin_request = {
        "request_id": f"req-{uuid.uuid4().hex[:12]}",
        "command": "gateway.pairing.begin",
        "client": "ghodex-gateway-live-acceptance",
        "requested_scopes": ["observe"],
    }
    begin_response = send_single_request_tcp(host, port, begin_request, timeout=timeout)
    pairing_code = (begin_response.get("result") or {}).get("pairing_code")
    if begin_response.get("status") != "ok" or not pairing_code:
        raise RuntimeError(
            "gateway.pairing.begin failed for live acceptance. "
            f"Response: {json.dumps(begin_response, sort_keys=True)}"
        )

    exchange_request = {
        "request_id": f"req-{uuid.uuid4().hex[:12]}",
        "command": "gateway.pairing.exchange",
        "pairing_code": pairing_code,
    }
    exchange_response = send_single_request_tcp(host, port, exchange_request, timeout=timeout)
    token = (exchange_response.get("result") or {}).get("token")
    if exchange_response.get("status") != "ok" or not token:
        raise RuntimeError(
            "gateway.pairing.exchange failed for live acceptance. "
            f"Response: {json.dumps(exchange_response, sort_keys=True)}"
        )

    return {
        "pairing_begin": begin_response,
        "pairing_exchange": exchange_response,
        "token": str(token),
        "token_preview": f"{str(token)[:8]}...",
    }


def snapshot_v2_has_marker(response: dict, marker: str) -> bool:
    result = response.get("result") or {}
    return (
        response.get("status") == "ok"
        and result.get("snapshot_format") == "ansi_text"
        and marker in (result.get("content") or "")
    )


def semantic_v2_has_marker(response: dict, marker: str) -> bool:
    result = response.get("result") or {}
    logical_lines = result.get("logical_lines") or []
    return (
        response.get("status") == "ok"
        and marker in (result.get("exact_text") or "")
        and any(marker in line for line in logical_lines)
    )


def wait_for_snapshot_v2(
    *,
    label: str,
    marker: str,
    timeout: float,
    fetch: Callable[[float], dict],
) -> dict:
    deadline = time.monotonic() + timeout
    last_response: dict | None = None
    while time.monotonic() < deadline:
        remaining = max(0.5, deadline - time.monotonic())
        response = fetch(remaining)
        last_response = response
        if snapshot_v2_has_marker(response, marker):
            return response
        time.sleep(0.25)

    raise RuntimeError(
        f"{label} content did not include marker before timeout: "
        f"{json.dumps(last_response or {}, sort_keys=True)}"
    )


def wait_for_semantic_v2(
    *,
    label: str,
    marker: str,
    timeout: float,
    fetch: Callable[[float], dict],
) -> dict:
    deadline = time.monotonic() + timeout
    last_response: dict | None = None
    while time.monotonic() < deadline:
        remaining = max(0.5, deadline - time.monotonic())
        response = fetch(remaining)
        last_response = response
        if semantic_v2_has_marker(response, marker):
            return response
        time.sleep(0.25)

    raise RuntimeError(
        f"{label} semantic payload did not include marker before timeout: "
        f"{json.dumps(last_response or {}, sort_keys=True)}"
    )


def run_acceptance(args: argparse.Namespace) -> dict:
    app_bundle = Path(args.app).resolve() if args.app else resolve_default_app()
    runtime_root = Path(args.runtime_root).resolve() if args.runtime_root else resolve_default_runtime_root()
    output_path = Path(args.output).expanduser().resolve()

    session_root = Path(f"/tmp/ghx-control-harness-gateway-{uuid.uuid4().hex[:8]}")
    home_dir = session_root / "home"
    app_support_root = session_root / "app-support"
    config_path = home_dir / ".config" / "ghostty" / "config"
    log_path = session_root / "app.log"

    proc: subprocess.Popen[str] | None = None
    local_stream_client: socket.socket | None = None
    gateway_tcp_stream_client: socket.socket | None = None
    ws_snapshot: WebSocketConnection | None = None
    ws_stream: WebSocketConnection | None = None

    result: dict = {
        "app": str(app_bundle),
        "runtime_root": str(runtime_root),
        "session_root": str(session_root),
        "log_path": str(log_path),
    }

    try:
        proc = launch_app(
            app_bundle,
            log_path,
            runtime_root=runtime_root,
            app_support_root=app_support_root,
            home_dir=home_dir,
            config_path=config_path,
        )
        result["pid"] = proc.pid

        socket_path = wait_for_harness_socket(proc.pid, timeout_ms=args.startup_timeout_ms)
        gateway_port = wait_for_gateway_port(proc.pid, timeout_ms=args.startup_timeout_ms)
        gateway_host = "127.0.0.1"
        result["socket_path"] = socket_path
        result["gateway"] = {"host": gateway_host, "port": gateway_port}

        terminal_id, initial_snapshot = wait_for_primary_terminal(
            app_bundle,
            socket_path,
            timeout_ms=args.startup_timeout_ms,
        )
        result["initial_snapshot"] = initial_snapshot
        result["terminal_id"] = terminal_id

        # Local unix-socket events.subscribe acceptance.
        local_seed = issue_run_command(
            app_bundle,
            socket_path,
            terminal_id=terminal_id,
            marker=f"GHX_LOCAL_EVENT_REPLAY_{uuid.uuid4().hex[:8]}",
            timeout_ms=args.startup_timeout_ms,
        )
        result["local_events_seed"] = local_seed

        local_stream_request = {
            "request_id": f"req-{uuid.uuid4().hex[:12]}",
            "command": "events.subscribe",
            "since_sequence": max(0, local_seed["sequence"] - 1),
            "event_limit": 8,
        }
        local_stream_client, local_reader, local_ack = open_line_subscription_unix(
            socket_path,
            local_stream_request,
            timeout=args.request_timeout,
        )
        if local_ack.get("status") != "ok":
            raise RuntimeError(f"local events.subscribe failed: {json.dumps(local_ack, sort_keys=True)}")
        result["local_events_subscribe_ack"] = local_ack

        local_replay = wait_for_event_line(
            local_reader,
            timeout_ms=args.stream_timeout_ms,
            predicate=lambda record: record.get("request_id") == local_seed["request_id"],
        )
        result["local_events_replay"] = local_replay

        local_live = issue_run_command(
            app_bundle,
            socket_path,
            terminal_id=terminal_id,
            marker=f"GHX_LOCAL_EVENT_LIVE_{uuid.uuid4().hex[:8]}",
            timeout_ms=args.startup_timeout_ms,
        )
        result["local_events_live_command"] = local_live
        local_live_event = wait_for_event_line(
            local_reader,
            timeout_ms=args.stream_timeout_ms,
            predicate=lambda record: record.get("request_id") == local_live["request_id"],
        )
        result["local_events_live"] = local_live_event

        # Gateway TCP handshake + token issuance.
        tcp_handshake = send_single_request_tcp(
            gateway_host,
            gateway_port,
            {"request_id": f"req-{uuid.uuid4().hex[:12]}", "command": "handshake"},
            timeout=args.request_timeout,
        )
        if tcp_handshake.get("status") != "ok":
            raise RuntimeError(f"gateway TCP handshake failed: {json.dumps(tcp_handshake, sort_keys=True)}")
        result["gateway_tcp_handshake"] = tcp_handshake

        token_bundle = issue_observe_token(gateway_host, gateway_port, timeout=args.request_timeout)
        auth_token = token_bundle["token"]
        result["gateway_auth"] = {
            "pairing_begin": token_bundle["pairing_begin"],
            "pairing_exchange": token_bundle["pairing_exchange"],
            "token_preview": token_bundle["token_preview"],
        }

        tcp_snapshot_seed = issue_run_command(
            app_bundle,
            socket_path,
            terminal_id=terminal_id,
            marker=f"GHX_GATEWAY_TCP_SNAPSHOT_{uuid.uuid4().hex[:8]}",
            timeout_ms=args.startup_timeout_ms,
        )
        result["gateway_tcp_snapshot_seed"] = tcp_snapshot_seed
        tcp_snapshot_request = {
            "request_id": f"req-{uuid.uuid4().hex[:12]}",
            "command": "terminal.snapshot.v2",
            "auth_token": auth_token,
            "terminal_id": terminal_id,
            "scope": "screen",
            "mode": "snapshot",
        }
        tcp_snapshot = wait_for_snapshot_v2(
            label="gateway TCP terminal.snapshot.v2",
            marker=tcp_snapshot_seed["marker"],
            timeout=args.request_timeout,
            fetch=lambda remaining: send_single_request_tcp(
                gateway_host,
                gateway_port,
                tcp_snapshot_request,
                timeout=min(args.request_timeout, remaining),
            ),
        )
        result["gateway_tcp_snapshot_v2"] = tcp_snapshot

        tcp_semantic_seed = issue_run_command(
            app_bundle,
            socket_path,
            terminal_id=terminal_id,
            marker=f"GHX_GATEWAY_TCP_SEMANTIC_{uuid.uuid4().hex[:8]}",
            timeout_ms=args.startup_timeout_ms,
        )
        result["gateway_tcp_semantic_seed"] = tcp_semantic_seed
        tcp_semantic_request = {
            "request_id": f"req-{uuid.uuid4().hex[:12]}",
            "command": "terminal.semantic.v2",
            "auth_token": auth_token,
            "terminal_id": terminal_id,
            "scope": "screen",
            "mode": "snapshot",
        }
        tcp_semantic = wait_for_semantic_v2(
            label="gateway TCP terminal.semantic.v2",
            marker=tcp_semantic_seed["marker"],
            timeout=args.request_timeout,
            fetch=lambda remaining: send_single_request_tcp(
                gateway_host,
                gateway_port,
                tcp_semantic_request,
                timeout=min(args.request_timeout, remaining),
            ),
        )
        result["gateway_tcp_semantic_v2"] = tcp_semantic

        tcp_seed = issue_run_command(
            app_bundle,
            socket_path,
            terminal_id=terminal_id,
            marker=f"GHX_GATEWAY_TCP_EVENT_REPLAY_{uuid.uuid4().hex[:8]}",
            timeout_ms=args.startup_timeout_ms,
        )
        result["gateway_tcp_events_seed"] = tcp_seed
        tcp_stream_request = {
            "request_id": f"req-{uuid.uuid4().hex[:12]}",
            "command": "events.subscribe",
            "auth_token": auth_token,
            "since_sequence": max(0, tcp_seed["sequence"] - 1),
            "event_limit": 8,
        }
        gateway_tcp_stream_client, gateway_tcp_reader, tcp_ack = open_line_subscription_tcp(
            gateway_host,
            gateway_port,
            tcp_stream_request,
            timeout=args.request_timeout,
        )
        if tcp_ack.get("status") != "ok":
            raise RuntimeError(f"gateway TCP events.subscribe failed: {json.dumps(tcp_ack, sort_keys=True)}")
        result["gateway_tcp_events_subscribe_ack"] = tcp_ack

        tcp_replay = wait_for_event_line(
            gateway_tcp_reader,
            timeout_ms=args.stream_timeout_ms,
            predicate=lambda record: record.get("request_id") == tcp_seed["request_id"],
        )
        result["gateway_tcp_events_replay"] = tcp_replay

        tcp_live = issue_run_command(
            app_bundle,
            socket_path,
            terminal_id=terminal_id,
            marker=f"GHX_GATEWAY_TCP_EVENT_LIVE_{uuid.uuid4().hex[:8]}",
            timeout_ms=args.startup_timeout_ms,
        )
        result["gateway_tcp_events_live_command"] = tcp_live
        tcp_live_event = wait_for_event_line(
            gateway_tcp_reader,
            timeout_ms=args.stream_timeout_ms,
            predicate=lambda record: record.get("request_id") == tcp_live["request_id"],
        )
        result["gateway_tcp_events_live"] = tcp_live_event

        # Gateway WebSocket handshake + authenticated one-shot/subscription coverage.
        ws_snapshot, ws_handshake = open_websocket(
            gateway_host,
            gateway_port,
            timeout=args.request_timeout,
        )
        result["gateway_websocket_handshake"] = ws_handshake

        ws_snapshot_seed = issue_run_command(
            app_bundle,
            socket_path,
            terminal_id=terminal_id,
            marker=f"GHX_GATEWAY_WS_SNAPSHOT_{uuid.uuid4().hex[:8]}",
            timeout_ms=args.startup_timeout_ms,
        )
        result["gateway_websocket_snapshot_seed"] = ws_snapshot_seed
        ws_snapshot_response = wait_for_snapshot_v2(
            label="gateway WebSocket terminal.snapshot.v2",
            marker=ws_snapshot_seed["marker"],
            timeout=args.request_timeout,
            fetch=lambda remaining: websocket_request(
                ws_snapshot,
                {
                    "request_id": f"req-{uuid.uuid4().hex[:12]}",
                    "command": "terminal.snapshot.v2",
                    "auth_token": auth_token,
                    "terminal_id": terminal_id,
                    "scope": "screen",
                    "mode": "snapshot",
                },
                timeout=remaining,
            ),
        )
        result["gateway_websocket_snapshot_v2"] = ws_snapshot_response

        ws_semantic_seed = issue_run_command(
            app_bundle,
            socket_path,
            terminal_id=terminal_id,
            marker=f"GHX_GATEWAY_WS_SEMANTIC_{uuid.uuid4().hex[:8]}",
            timeout_ms=args.startup_timeout_ms,
        )
        result["gateway_websocket_semantic_seed"] = ws_semantic_seed
        ws_semantic_response = wait_for_semantic_v2(
            label="gateway WebSocket terminal.semantic.v2",
            marker=ws_semantic_seed["marker"],
            timeout=args.request_timeout,
            fetch=lambda remaining: websocket_request(
                ws_snapshot,
                {
                    "request_id": f"req-{uuid.uuid4().hex[:12]}",
                    "command": "terminal.semantic.v2",
                    "auth_token": auth_token,
                    "terminal_id": terminal_id,
                    "scope": "screen",
                    "mode": "snapshot",
                },
                timeout=remaining,
            ),
        )
        result["gateway_websocket_semantic_v2"] = ws_semantic_response

        ws_seed = issue_run_command(
            app_bundle,
            socket_path,
            terminal_id=terminal_id,
            marker=f"GHX_GATEWAY_WS_EVENT_REPLAY_{uuid.uuid4().hex[:8]}",
            timeout_ms=args.startup_timeout_ms,
        )
        result["gateway_websocket_events_seed"] = ws_seed
        ws_stream, _ = open_websocket(gateway_host, gateway_port, timeout=args.request_timeout)
        ws_stream.send_text(
            {
                "request_id": f"req-{uuid.uuid4().hex[:12]}",
                "command": "events.subscribe",
                "auth_token": auth_token,
                "since_sequence": max(0, ws_seed["sequence"] - 1),
                "event_limit": 8,
            }
        )
        ws_ack = ws_stream.read_json(timeout=args.request_timeout)
        if ws_ack.get("status") != "ok":
            raise RuntimeError(f"gateway WebSocket events.subscribe failed: {json.dumps(ws_ack, sort_keys=True)}")
        result["gateway_websocket_events_subscribe_ack"] = ws_ack

        ws_replay = wait_for_event_ws(
            ws_stream,
            timeout_ms=args.stream_timeout_ms,
            predicate=lambda record: record.get("request_id") == ws_seed["request_id"],
        )
        result["gateway_websocket_events_replay"] = ws_replay

        ws_live = issue_run_command(
            app_bundle,
            socket_path,
            terminal_id=terminal_id,
            marker=f"GHX_GATEWAY_WS_EVENT_LIVE_{uuid.uuid4().hex[:8]}",
            timeout_ms=args.startup_timeout_ms,
        )
        result["gateway_websocket_events_live_command"] = ws_live
        ws_live_event = wait_for_event_ws(
            ws_stream,
            timeout_ms=args.stream_timeout_ms,
            predicate=lambda record: record.get("request_id") == ws_live["request_id"],
        )
        result["gateway_websocket_events_live"] = ws_live_event

        log_text = log_path.read_text(encoding="utf-8", errors="replace")
        result["log_has_invalid_field"] = "invalid field" in log_text
        result["status"] = "passed"
        return result
    finally:
        if local_stream_client is not None:
            try:
                local_stream_client.close()
            except OSError:
                pass
        if gateway_tcp_stream_client is not None:
            try:
                gateway_tcp_stream_client.close()
            except OSError:
                pass
        if ws_snapshot is not None:
            ws_snapshot.close()
        if ws_stream is not None:
            ws_stream.close()
        if proc is not None:
            terminate_process(proc)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(json.dumps(result, indent=2, sort_keys=False), encoding="utf-8")


def main() -> None:
    args = parse_args()
    result = run_acceptance(args)
    print(json.dumps(result, indent=2, sort_keys=False))


if __name__ == "__main__":
    main()
