#!/usr/bin/env python3

"""
Control Harness terminal V2 live acceptance harness.

This harness launches an isolated GhoDex.app, discovers the live control
harness socket, and proves the terminal V2 surface works against a real app:

- `terminal.snapshot.v2` returns ANSI snapshot content
- `terminal.semantic.v2` returns exact text plus logical lines
- `terminal.stream.open` returns stream metadata and a seed replay chunk
- `terminal.stream.ack` succeeds for the opened stream
- a live terminal write produces a streamed `terminal_chunk` record
"""

from __future__ import annotations

import argparse
import json
import os
import re
import socket
import subprocess
import time
import uuid
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = "/tmp/ghx-control-harness-terminal-v2-live-acceptance.json"
HARNESS_SOCKET_RE = re.compile(r"(?P<path>/Users/.*/ControlHarness/harness\.sock)$")


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
        description="Prove terminal V2 Control Harness commands against a live GhoDex app."
    )
    parser.add_argument(
        "--app",
        default=None,
        help="Path to the GhoDex.app bundle to launch.",
    )
    parser.add_argument(
        "--runtime-root",
        default=None,
        help="CEF runtime root passed through GHODEX_CEF_ROOT.",
    )
    parser.add_argument(
        "--startup-timeout-ms",
        type=int,
        default=30000,
        help="Timeout budget for app launch and harness socket discovery.",
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
        help="Timeout budget for streamed replay/live chunks.",
    )
    parser.add_argument(
        "--output",
        default=DEFAULT_OUTPUT,
        help="Where to write the JSON artifact.",
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
        raise RuntimeError("socket closed before a line was received")
    line, _, _ = data.partition(b"\n")
    return line.decode().strip()


def recv_until_close(sock: socket.socket) -> str:
    data = b""
    while True:
        chunk = sock.recv(65536)
        if not chunk:
            break
        data += chunk
    if not data:
        raise RuntimeError("socket closed before a response body was received")
    return data.decode().strip()


def send_single_request(socket_path: str, body: dict, *, timeout: float) -> dict:
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(timeout)
    client.connect(socket_path)
    client.sendall((json.dumps(body) + "\n").encode())
    client.shutdown(socket.SHUT_WR)
    response_text = recv_until_close(client)
    client.close()
    return json.loads(response_text)


def open_subscription(socket_path: str, body: dict, *, timeout: float) -> tuple[socket.socket, dict]:
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(timeout)
    client.connect(socket_path)
    client.sendall((json.dumps(body) + "\n").encode())
    client.shutdown(socket.SHUT_WR)
    ack = json.loads(recv_line(client))
    return client, ack


def wait_for_stream_chunk(
    client: socket.socket,
    *,
    timeout_ms: int,
    predicate,
) -> dict:
    deadline = time.monotonic() + (timeout_ms / 1000.0)
    observed: list[dict] = []
    while time.monotonic() < deadline:
        remaining = max(0.1, deadline - time.monotonic())
        client.settimeout(remaining)
        try:
            line = recv_line(client)
        except TimeoutError:
            continue
        except socket.timeout:
            continue

        record = json.loads(line)
        observed.append(record)
        if predicate(record):
            matched = dict(record)
            matched["_observed_records"] = list(observed)
            return matched

    raise RuntimeError(
        "Timed out waiting for expected stream chunk. "
        f"Observed {len(observed)} record(s): {json.dumps(observed[-3:], sort_keys=True)}"
    )


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
        "\n".join(
            [
                "initial-window = true",
                "quit-after-last-window-closed = false",
                "",
            ]
        ),
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
        snapshot = run_control_command(app_bundle, socket_path, "state.snapshot")
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
            "terminal.read",
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


def run_acceptance(args: argparse.Namespace) -> dict:
    app_bundle = Path(args.app).resolve() if args.app else resolve_default_app()
    runtime_root = Path(args.runtime_root).resolve() if args.runtime_root else resolve_default_runtime_root()
    output_path = Path(args.output).expanduser().resolve()

    session_root = Path(f"/tmp/ghx-control-harness-v2-{uuid.uuid4().hex[:8]}")
    home_dir = session_root / "home"
    app_support_root = session_root / "app-support"
    config_path = home_dir / ".config" / "ghostty" / "config"
    log_path = session_root / "app.log"

    proc: subprocess.Popen[str] | None = None
    stream_client: socket.socket | None = None
    result = {
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
        result["socket_path"] = socket_path

        terminal_id, initial_snapshot = wait_for_primary_terminal(
            app_bundle,
            socket_path,
            timeout_ms=args.startup_timeout_ms,
        )
        result["initial_snapshot"] = initial_snapshot
        result["terminal_id"] = terminal_id

        seed_marker = f"GHX_V2_STREAM_SEED_{uuid.uuid4().hex[:8]}"
        seed_command = run_control_command(
            app_bundle,
            socket_path,
            "terminal.command.run",
            f"--terminal-id={terminal_id}",
            f"--command=printf {seed_marker}\\\\n",
        )
        seed_write_id = seed_command["result"]["write_id"]
        result["seed_command"] = seed_command
        result["seed_settle"] = wait_for_write_settle(
            app_bundle,
            socket_path,
            terminal_id=terminal_id,
            write_id=seed_write_id,
            timeout_ms=args.startup_timeout_ms,
        )

        snapshot_marker = f"GHX_V2_SNAPSHOT_{uuid.uuid4().hex[:8]}"
        snapshot_command = run_control_command(
            app_bundle,
            socket_path,
            "terminal.command.run",
            f"--terminal-id={terminal_id}",
            f"--command=printf {snapshot_marker}\\\\n",
        )
        snapshot_write_id = snapshot_command["result"]["write_id"]
        result["snapshot_command"] = snapshot_command
        result["snapshot_settle"] = wait_for_write_settle(
            app_bundle,
            socket_path,
            terminal_id=terminal_id,
            write_id=snapshot_write_id,
            timeout_ms=args.startup_timeout_ms,
        )

        snapshot_request = {
            "request_id": f"req-{uuid.uuid4().hex[:12]}",
            "command": "terminal.snapshot.v2",
            "terminal_id": terminal_id,
            "scope": "screen",
            "mode": "snapshot",
        }
        snapshot_response = send_single_request(
            socket_path,
            snapshot_request,
            timeout=args.request_timeout,
        )
        snapshot_result = snapshot_response.get("result") or {}
        if snapshot_response.get("status") != "ok":
            raise RuntimeError(
                f"terminal.snapshot.v2 failed: {json.dumps(snapshot_response, sort_keys=True)}"
            )
        if snapshot_result.get("snapshot_format") != "ansi_text":
            raise RuntimeError(
                f"terminal.snapshot.v2 returned unexpected format: {json.dumps(snapshot_response, sort_keys=True)}"
            )
        if snapshot_marker not in (snapshot_result.get("content") or ""):
            raise RuntimeError(
                "terminal.snapshot.v2 content did not include snapshot marker. "
                f"Response: {json.dumps(snapshot_response, sort_keys=True)}"
            )
        result["terminal_snapshot_v2"] = snapshot_response

        semantic_marker = f"GHX_V2_SEMANTIC_{uuid.uuid4().hex[:8]}"
        semantic_command = run_control_command(
            app_bundle,
            socket_path,
            "terminal.command.run",
            f"--terminal-id={terminal_id}",
            f"--command=printf {semantic_marker}\\\\n",
        )
        semantic_write_id = semantic_command["result"]["write_id"]
        result["semantic_command"] = semantic_command
        result["semantic_settle"] = wait_for_write_settle(
            app_bundle,
            socket_path,
            terminal_id=terminal_id,
            write_id=semantic_write_id,
            timeout_ms=args.startup_timeout_ms,
        )

        semantic_request = {
            "request_id": f"req-{uuid.uuid4().hex[:12]}",
            "command": "terminal.semantic.v2",
            "terminal_id": terminal_id,
            "scope": "screen",
            "mode": "snapshot",
        }
        semantic_response = send_single_request(
            socket_path,
            semantic_request,
            timeout=args.request_timeout,
        )
        semantic_result = semantic_response.get("result") or {}
        logical_lines = semantic_result.get("logical_lines") or []
        if semantic_response.get("status") != "ok":
            raise RuntimeError(
                f"terminal.semantic.v2 failed: {json.dumps(semantic_response, sort_keys=True)}"
            )
        if semantic_marker not in (semantic_result.get("exact_text") or ""):
            raise RuntimeError(
                "terminal.semantic.v2 exact_text did not include semantic marker. "
                f"Response: {json.dumps(semantic_response, sort_keys=True)}"
            )
        if not any(semantic_marker in line for line in logical_lines):
            raise RuntimeError(
                "terminal.semantic.v2 logical_lines did not include semantic marker. "
                f"Response: {json.dumps(semantic_response, sort_keys=True)}"
            )
        result["terminal_semantic_v2"] = semantic_response

        stream_request = {
            "request_id": f"req-{uuid.uuid4().hex[:12]}",
            "command": "terminal.stream.open",
            "terminal_id": terminal_id,
        }
        stream_client, stream_ack = open_subscription(
            socket_path,
            stream_request,
            timeout=args.request_timeout,
        )
        if stream_ack.get("status") != "ok":
            raise RuntimeError(
                f"terminal.stream.open failed: {json.dumps(stream_ack, sort_keys=True)}"
            )
        stream_result = stream_ack.get("result") or {}
        stream_id = stream_result.get("stream_id")
        if not stream_id:
            raise RuntimeError(
                f"terminal.stream.open did not return stream_id: {json.dumps(stream_ack, sort_keys=True)}"
            )
        result["terminal_stream_open"] = stream_ack

        seed_chunk = wait_for_stream_chunk(
            stream_client,
            timeout_ms=args.stream_timeout_ms,
            predicate=lambda record: (
                record.get("stream_kind") == "terminal_chunk"
                and record.get("stream_id") == stream_id
                and seed_marker in (record.get("content") or "")
            ),
        )
        result["terminal_stream_seed_chunk"] = seed_chunk

        stream_ack_request = {
            "request_id": f"req-{uuid.uuid4().hex[:12]}",
            "command": "terminal.stream.ack",
            "terminal_id": terminal_id,
            "stream_id": stream_id,
            "ack_bytes": max(1, int(seed_chunk.get("content_length") or 1)),
        }
        stream_ack_response = send_single_request(
            socket_path,
            stream_ack_request,
            timeout=args.request_timeout,
        )
        if stream_ack_response.get("status") != "ok":
            raise RuntimeError(
                f"terminal.stream.ack failed: {json.dumps(stream_ack_response, sort_keys=True)}"
            )
        result["terminal_stream_ack"] = stream_ack_response

        live_marker = f"GHX_V2_STREAM_LIVE_{uuid.uuid4().hex[:8]}"
        live_command = run_control_command(
            app_bundle,
            socket_path,
            "terminal.command.run",
            f"--terminal-id={terminal_id}",
            f"--command=printf {live_marker}\\\\n",
        )
        result["live_command"] = live_command

        live_chunk = wait_for_stream_chunk(
            stream_client,
            timeout_ms=args.stream_timeout_ms,
            predicate=lambda record: (
                record.get("stream_kind") == "terminal_chunk"
                and record.get("stream_id") == stream_id
                and live_marker in (record.get("content") or "")
            ),
        )
        result["terminal_stream_live_chunk"] = live_chunk

        log_text = log_path.read_text(encoding="utf-8", errors="replace")
        result["log_has_invalid_field"] = "invalid field" in log_text
        result["status"] = "passed"
        return result
    finally:
        if stream_client is not None:
            try:
                stream_client.close()
            except OSError:
                pass
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
