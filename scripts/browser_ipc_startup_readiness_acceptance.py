#!/usr/bin/env python3

"""
Browser IPC startup readiness acceptance harness.

This harness forces the launch-time Remote Pairing QR path into a deterministic
failure mode and proves that Browser IPC stays responsive anyway. It exists to
catch startup regressions where a launch-time modal blocks `@MainActor` before
Browser control requests such as `listContexts` or `newContext` can run.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import socket
import subprocess
import time
import uuid
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = "/tmp/ghx-browser-ipc-startup-readiness-acceptance.json"


def resolve_default_app() -> Path:
    app = REPO_ROOT / "macos" / "build" / "Debug" / "GhoDex.app"
    if not app.exists():
        raise SystemExit(
            "No built GhoDex.app found at macos/build/Debug/GhoDex.app. "
            "Pass --app=/path/to/GhoDex.app."
        )
    return app


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Prove launch-time Remote Pairing QR failures do not block Browser IPC startup."
    )
    parser.add_argument("--app", default=None, help="Path to the CEF-enabled GhoDex.app bundle to launch.")
    parser.add_argument(
        "--runtime-root",
        default=str(REPO_ROOT / "macos" / "build" / "cef-runtime" / "current"),
        help="CEF runtime root passed through GHODEX_CEF_ROOT.",
    )
    parser.add_argument(
        "--request-timeout",
        type=float,
        default=5.0,
        help="Per-request timeout in seconds.",
    )
    parser.add_argument(
        "--startup-timeout-ms",
        type=int,
        default=30000,
        help="Timeout budget for socket creation and repeated IPC probes.",
    )
    parser.add_argument("--output", default=DEFAULT_OUTPUT, help="Where to write the JSON artifact.")
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
    version: str,
    timeout: float,
) -> dict:
    body = {
        "id": str(uuid.uuid4()),
        "version": version,
        "command": command,
        "payload": {},
    }
    started = time.perf_counter()
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(timeout)
    client.connect(socket_path)
    client.sendall((json.dumps(body) + "\n").encode())
    line = recv_line(client)
    client.close()
    elapsed_ms = round((time.perf_counter() - started) * 1000, 2)
    return {"elapsed_ms": elapsed_ms, "request": body, "response": json.loads(line)}


def wait_for_successful_probe(
    socket_path: str,
    *,
    version: str,
    command: str,
    timeout_ms: int,
    request_timeout: float,
) -> dict:
    deadline = time.monotonic() + (timeout_ms / 1000.0)
    last_error: str | None = None
    while time.monotonic() < deadline:
        if os.path.exists(socket_path):
            try:
                return send_request(
                    socket_path,
                    command,
                    version=version,
                    timeout=request_timeout,
                )
            except Exception as exc:  # noqa: BLE001
                last_error = str(exc)
        time.sleep(0.25)
    raise RuntimeError(
        f"Timed out waiting for {version} {command} readiness at {socket_path}: "
        f"{last_error or 'no socket'}"
    )


def send_request_with_retry(
    socket_path: str,
    *,
    version: str,
    command: str,
    timeout_ms: int,
    request_timeout: float,
) -> dict:
    deadline = time.monotonic() + (timeout_ms / 1000.0)
    last_error: str | None = None

    while time.monotonic() < deadline:
        remaining = max(0.5, deadline - time.monotonic())
        try:
            return send_request(
                socket_path,
                command,
                version=version,
                timeout=min(request_timeout, remaining),
            )
        except Exception as exc:  # noqa: BLE001
            last_error = str(exc)
            time.sleep(0.25)

    raise RuntimeError(
        f"Timed out waiting for stable {version} {command} response at {socket_path}: "
        f"{last_error or 'no response'}"
    )


def terminate_process(proc: subprocess.Popen[str], timeout: float = 15.0) -> None:
    if proc.poll() is not None:
        return
    proc.terminate()
    deadline = time.time() + timeout / 2
    while time.time() < deadline:
        if proc.poll() is not None:
            return
        time.sleep(0.25)

    proc.kill()
    deadline = time.time() + timeout / 2
    while time.time() < deadline:
        if proc.poll() is not None:
            return
        time.sleep(0.25)

    raise RuntimeError(f"Process {proc.pid} did not exit in time")


def launch_app(
    app_bundle: Path,
    log_path: Path,
    *,
    runtime_root: str,
    app_support_root: Path,
    home_dir: Path,
) -> subprocess.Popen[str]:
    executable = app_bundle / "Contents" / "MacOS" / "GhoDex"
    if not executable.exists():
        raise RuntimeError(f"App executable does not exist: {executable}")

    env = os.environ.copy()
    env["GHODEX_CEF_ROOT"] = runtime_root
    env["GHODEX_BROWSER_APP_SUPPORT_ROOT"] = str(app_support_root)
    env["GHODEX_CONTROL_HARNESS_PAIRING_QR_ON_LAUNCH"] = "1"
    env["GHODEX_CONTROL_HARNESS_GATEWAY_HOST"] = "127.0.0.1"
    env["HOME"] = str(home_dir)
    env["TMPDIR"] = str(home_dir / "tmp")
    env.pop("GHODEX_CEF_PROFILE_PATH", None)

    home_dir.mkdir(parents=True, exist_ok=True)
    (home_dir / "tmp").mkdir(parents=True, exist_ok=True)
    app_support_root.mkdir(parents=True, exist_ok=True)
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


def run_acceptance(args: argparse.Namespace) -> dict:
    app_bundle = Path(args.app).resolve() if args.app else resolve_default_app()
    runtime_root = str(Path(args.runtime_root).resolve())
    output_path = Path(args.output).expanduser().resolve()

    session_root = Path(f"/tmp/ghx-browser-ipc-start-{uuid.uuid4().hex[:8]}")
    if session_root.exists():
        shutil.rmtree(session_root, ignore_errors=True)
    session_root.mkdir(parents=True, exist_ok=True)
    home_dir = session_root / "home"
    app_support_root = session_root / "app-support"
    log_path = session_root / "app.log"
    socket_path = app_support_root / "browser-control.sock"

    artifact: dict[str, object] = {
        "app": str(app_bundle),
        "runtime_root": runtime_root,
        "session_root": str(session_root),
        "log_path": str(log_path),
        "socket_path": str(socket_path),
        "status": "running",
        "forced_launch_failure": {
            "GHODEX_CONTROL_HARNESS_PAIRING_QR_ON_LAUNCH": "1",
            "GHODEX_CONTROL_HARNESS_GATEWAY_HOST": "127.0.0.1",
        },
    }

    proc: subprocess.Popen[str] | None = None
    try:
        proc = launch_app(
            app_bundle,
            log_path,
            runtime_root=runtime_root,
            app_support_root=app_support_root,
            home_dir=home_dir,
        )
        artifact["pid"] = proc.pid

        initial_probe = wait_for_successful_probe(
            str(socket_path),
            version="browser.context.v2",
            command="listContexts",
            timeout_ms=args.startup_timeout_ms,
            request_timeout=args.request_timeout,
        )
        follow_up_probe_timeout_ms = max(
            args.startup_timeout_ms // 2,
            int(args.request_timeout * 3000),
        )
        follow_up_context_probes = [
            send_request_with_retry(
                str(socket_path),
                command="listContexts",
                version="browser.context.v2",
                timeout_ms=follow_up_probe_timeout_ms,
                request_timeout=args.request_timeout,
            )
            for _ in range(3)
        ]
        legacy_tab_probe = send_request_with_retry(
            str(socket_path),
            command="listTabs",
            version="browser.tab.v1",
            timeout_ms=follow_up_probe_timeout_ms,
            request_timeout=args.request_timeout,
        )

        artifact["initial_context_probe"] = initial_probe
        artifact["follow_up_context_probes"] = follow_up_context_probes
        artifact["legacy_tab_probe"] = legacy_tab_probe
        artifact["status"] = "passed"
    except Exception as exc:  # noqa: BLE001
        artifact["status"] = "failed"
        artifact["error"] = str(exc)
        if log_path.exists():
            artifact["log_tail"] = log_path.read_text(encoding="utf-8", errors="replace").splitlines()[-40:]
        raise
    finally:
        if proc is not None:
            terminate_process(proc)
        output_path.write_text(json.dumps(artifact, indent=2), encoding="utf-8")

    return artifact


def main() -> int:
    args = parse_args()
    run_acceptance(args)
    print(json.dumps(json.loads(Path(args.output).read_text(encoding="utf-8")), indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
