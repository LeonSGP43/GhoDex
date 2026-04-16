#!/usr/bin/env python3

"""
Control Harness canonical protocol surface live acceptance harness.

This harness launches an isolated GhoDex.app and proves the non-browser public
ControlHarness surface against a real app instance. It focuses on the canonical
namespaced commands that previously relied mainly on unit tests:

- system/app discovery and relaunch
- workspace tab and core terminal mutations
- runtime session/task/schedule control
- todo mutations and stale-sync flow
- window and panel control
- settings stage/validate/apply/reset/diff
- diagnostics metrics/log/audit access
- buffered events.stream subscribe/drain/unsubscribe

The remaining browser-specific live gates stay in their dedicated scripts.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import signal
import socket
import subprocess
import time
import uuid
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Callable


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = "/tmp/ghx-control-harness-protocol-surface-live-acceptance.json"
HARNESS_SOCKET_RE = re.compile(r"(?P<path>/Users/.*/ControlHarness/harness\.sock)$")
READ_ONLY_RETRYABLE_COMMANDS = {
    "system.handshake",
    "system.target.resolve",
    "system.capabilities.get",
    "app.state.get",
    "state.snapshot",
    "terminal.read",
    "terminal.snapshot",
    "terminal.semantic",
    "window.list",
    "panel.list",
    "panel.state.get",
    "settings.schema.get",
    "settings.values.get",
    "settings.diff",
    "runtime.snapshot",
    "todo.snapshot",
    "diagnostics.metrics.get",
    "diagnostics.logs.tail",
    "diagnostics.logs.query",
    "diagnostics.errors.recent",
    "diagnostics.audit.query",
    "diagnostics.eventBuffer.status",
}


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

    raise SystemExit("No default CEF runtime root found. Pass --runtime-root=/path/to/runtime.")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Prove canonical non-browser ControlHarness protocol commands against a live GhoDex app."
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
        help="Timeout budget for app launch and harness socket discovery.",
    )
    parser.add_argument(
        "--request-timeout",
        type=float,
        default=12.0,
        help="Per-request timeout in seconds.",
    )
    parser.add_argument(
        "--settle-ms",
        type=int,
        default=12000,
        help="Timeout budget for state-change settle loops.",
    )
    parser.add_argument(
        "--output",
        default=DEFAULT_OUTPUT,
        help="Where to write the JSON artifact.",
    )
    parser.add_argument(
        "--keep-failed-session",
        action="store_true",
        help="Preserve the launched app/session root on failure for live post-mortem inspection.",
    )
    parser.add_argument(
        "--skip-related-diagnostics-gate",
        action="store_true",
        help="Skip the dedicated diagnostics governance live gate that complements the canonical protocol surface run.",
    )
    return parser.parse_args()


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


def send_single_request(socket_path: str, body: dict[str, Any], *, timeout: float) -> dict[str, Any]:
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(timeout)
    client.connect(socket_path)
    client.sendall((json.dumps(body) + "\n").encode())
    client.shutdown(socket.SHUT_WR)
    response_text = recv_until_close(client)
    client.close()
    return json.loads(response_text)


def socket_accepts_connections(socket_path: str, *, timeout: float = 1.0) -> bool:
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(timeout)
    try:
        client.connect(socket_path)
    except OSError:
        client.close()
        return False

    client.close()
    return True


def run_related_gate(
    script_name: str,
    *,
    app_bundle: Path,
    output_path: Path,
    startup_timeout_ms: int,
    request_timeout: float,
    settle_ms: int,
) -> dict[str, Any]:
    script_path = REPO_ROOT / "scripts" / script_name
    command = [
        "python3",
        str(script_path),
        "--app",
        str(app_bundle),
        "--startup-timeout-ms",
        str(startup_timeout_ms),
        "--request-timeout",
        str(request_timeout),
        "--settle-ms",
        str(settle_ms),
        "--output",
        str(output_path),
    ]
    completed = subprocess.run(
        command,
        cwd=str(REPO_ROOT),
        capture_output=True,
        text=True,
        check=False,
    )

    child_artifact: dict[str, Any] | None = None
    if output_path.exists():
        try:
            child_artifact = json.loads(output_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            child_artifact = None

    result = {
        "script": f"scripts/{script_name}",
        "artifact_path": str(output_path),
        "return_code": completed.returncode,
        "status": child_artifact.get("status") if child_artifact else None,
        "stdout_tail": completed.stdout.splitlines()[-40:],
        "stderr_tail": completed.stderr.splitlines()[-40:],
    }
    if child_artifact is not None and "summary" in child_artifact:
        result["summary"] = child_artifact["summary"]

    if completed.returncode != 0:
        raise RuntimeError(f"{script_name} exited with code {completed.returncode}")
    if child_artifact is None:
        raise RuntimeError(f"{script_name} did not produce a readable artifact at {output_path}")
    if child_artifact.get("status") != "ok":
        raise RuntimeError(f"{script_name} finished without ok status")

    return result


class SocketLineReader:
    def __init__(self, sock: socket.socket) -> None:
        self.sock = sock
        self.buffer = b""

    def recv_line(self) -> str:
        while b"\n" not in self.buffer:
            chunk = self.sock.recv(65536)
            if not chunk:
                break
            self.buffer += chunk
        if not self.buffer:
            raise RuntimeError("socket closed before a line was received")
        line, sep, remainder = self.buffer.partition(b"\n")
        self.buffer = remainder if sep else b""
        return line.decode().strip()


def open_line_subscription(socket_path: str, body: dict[str, Any], *, timeout: float) -> tuple[socket.socket, SocketLineReader, dict[str, Any]]:
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(timeout)
    client.connect(socket_path)
    client.sendall((json.dumps(body) + "\n").encode())
    client.shutdown(socket.SHUT_WR)
    reader = SocketLineReader(client)
    ack = json.loads(reader.recv_line())
    return client, reader, ack


def wait_for_event_line(
    reader: SocketLineReader,
    *,
    timeout_ms: int,
    predicate: Callable[[dict[str, Any]], bool],
) -> dict[str, Any]:
    deadline = time.monotonic() + (timeout_ms / 1000.0)
    observed: list[dict[str, Any]] = []
    while time.monotonic() < deadline:
        remaining = max(0.05, deadline - time.monotonic())
        reader.sock.settimeout(remaining)
        try:
            record = json.loads(reader.recv_line())
        except TimeoutError:
            continue
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


def terminate_pid(pid: int, timeout: float = 15.0) -> None:
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return

    deadline = time.time() + (timeout / 2)
    while time.time() < deadline:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return
        time.sleep(0.25)

    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        return

    deadline = time.time() + (timeout / 2)
    while time.time() < deadline:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return
        time.sleep(0.25)

    raise RuntimeError(f"Process {pid} did not exit in time")


def pid_is_alive(pid: int | None) -> bool:
    if pid is None:
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def tail_text(path: Path, *, max_lines: int = 120) -> list[str]:
    if not path.exists():
        return []
    try:
        return path.read_text(encoding="utf-8", errors="replace").splitlines()[-max_lines:]
    except OSError:
        return []


def write_artifact(output_path: Path, artifact: dict[str, Any]) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(artifact, indent=2, sort_keys=True), encoding="utf-8")


def create_isolated_todo_workspace(root_path: Path) -> Path:
    workspace_root = root_path.resolve()
    days_dir = workspace_root / "days"
    days_dir.mkdir(parents=True, exist_ok=True)

    readme_path = workspace_root / "README.md"
    if not readme_path.exists():
        readme_path.write_text(
            "# GhoDex Todo Workspace\n\nDaily todo files live under `days/YYYY-MM-DD.json`.\n",
            encoding="utf-8",
        )

    creator_path = workspace_root / "creator.md"
    if not creator_path.exists():
        creator_path.write_text(
            "\n".join(
                [
                    "# creator",
                    "",
                    "## Why this folder exists",
                    "This workspace stores isolated live-acceptance todo files for GhoDex.",
                    "",
                    "## Created by",
                    "scripts/control_harness_protocol_surface_live_acceptance.py",
                    "",
                    "## Creation date",
                    date.today().isoformat(),
                    "",
                    "## Scope",
                    "- Store date-based todo files under `days/`.",
                    "- Keep protocol-surface acceptance isolated from user todo data.",
                    "",
                ]
            ),
            encoding="utf-8",
        )

    return workspace_root


def process_snapshot(pid: int | None) -> str | None:
    if pid is None:
        return None
    completed = subprocess.run(
        ["ps", "-p", str(pid), "-o", "pid=,ppid=,stat=,etime=,command="],
        capture_output=True,
        text=True,
        check=False,
    )
    snapshot = completed.stdout.strip()
    return snapshot or None


def launch_app(
    app_bundle: Path,
    log_path: Path,
    *,
    runtime_root: Path | None,
    app_support_root: Path,
    home_dir: Path,
    config_path: Path,
    todo_workspace_root: Path,
) -> subprocess.Popen[str]:
    executable = app_bundle / "Contents" / "MacOS" / "GhoDex"
    if not executable.exists():
        raise RuntimeError(f"App executable does not exist: {executable}")

    env = os.environ.copy()
    env["GHODEX_BROWSER_APP_SUPPORT_ROOT"] = str(app_support_root)
    env["GHOSTTY_CONFIG_PATH"] = str(config_path)
    env["HOME"] = str(home_dir)
    env["TMPDIR"] = str(home_dir / "tmp")
    if runtime_root is not None:
        env["GHODEX_CEF_ROOT"] = str(runtime_root)
    else:
        env.pop("GHODEX_CEF_ROOT", None)
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
                "ghodex-todo-enabled = true",
                f"ghodex-todo-workspace-root-path = {json.dumps(str(todo_workspace_root))}",
                "ghodex-todo-show-completed-items = true",
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
                socket_path = match.group("path")
                if os.path.exists(socket_path) and socket_accepts_connections(socket_path):
                    return socket_path
        time.sleep(0.25)

    raise RuntimeError(
        f"Timed out waiting for Control Harness socket for pid {pid}. "
        f"Last lsof sample: {last_lsof[-400:]}"
    )


def iso8601_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def iso8601_past(seconds: int) -> str:
    return (
        datetime.now(timezone.utc).replace(microsecond=0) - timedelta(seconds=seconds)
    ).isoformat().replace("+00:00", "Z")


def today_strings() -> tuple[str, str]:
    today_value = date.today()
    return today_value.isoformat(), (today_value - timedelta(days=1)).isoformat()


class HarnessClient:
    def __init__(self, socket_path: str, *, timeout: float, artifact: dict[str, Any]):
        self.socket_path = socket_path
        self.timeout = timeout
        self.artifact = artifact
        self.artifact.setdefault("requests", {})
        self.artifact.setdefault("request_order", [])
        self.artifact.setdefault("request_retries", [])

    def set_socket(self, socket_path: str) -> None:
        self.socket_path = socket_path

    def request(self, command: str, **fields: Any) -> dict[str, Any]:
        label = fields.pop("_label", command)
        body: dict[str, Any] = {
            "request_id": f"req-{uuid.uuid4().hex[:12]}",
            "command": command,
        }
        for key, value in fields.items():
            if value is not None:
                body[key] = value

        self.artifact["last_request_label"] = label
        self.artifact["last_request_command"] = command
        self.artifact["request_order"].append(label)
        response: dict[str, Any] | None = None
        attempt_count = 0
        max_attempts = 3 if command in READ_ONLY_RETRYABLE_COMMANDS else 1
        for attempt in range(1, max_attempts + 1):
            attempt_count = attempt
            try:
                response = send_single_request(self.socket_path, body, timeout=self.timeout)
                break
            except TimeoutError as exc:
                if attempt >= max_attempts:
                    raise
                self.artifact["request_retries"].append(
                    {
                        "label": label,
                        "command": command,
                        "attempt": attempt,
                        "reason": str(exc) or "timed out",
                    }
                )
                time.sleep(0.5 * attempt)

        if response is None:
            raise RuntimeError(f"{command} did not produce a response after {max_attempts} attempt(s)")
        self.artifact["requests"][label] = {
            "request": body,
            "response": response,
            "attempt_count": attempt_count,
        }
        self.artifact["last_successful_request_label"] = label
        self.artifact["last_successful_request_command"] = command
        if response.get("status") != "ok":
            raise RuntimeError(
                f"{command} failed: {json.dumps(response, ensure_ascii=False, sort_keys=True)}"
            )
        return response


def wait_until(
    description: str,
    predicate: Callable[[], Any],
    *,
    timeout_ms: int,
    interval_s: float = 0.25,
) -> Any:
    deadline = time.monotonic() + (timeout_ms / 1000.0)
    last_error: str | None = None
    while time.monotonic() < deadline:
        try:
            value = predicate()
            if value:
                return value
        except Exception as exc:  # noqa: BLE001
            last_error = str(exc)
        time.sleep(interval_s)
    raise RuntimeError(f"Timed out waiting for {description}. Last error: {last_error or 'none'}")


def wait_for_expected_target_pid(
    client: "HarnessClient",
    *,
    expected_pid: int,
    timeout_ms: int,
) -> dict[str, Any]:
    return wait_until(
        f"system.target.resolve pid={expected_pid}",
        lambda: (
            response
            if int(response.get("result", {}).get("instance", {}).get("process_id") or -1) == expected_pid
            else None
        )
        if (response := client.request("system.target.resolve", _label="system.target.resolve.expected-pid"))
        else None,
        timeout_ms=timeout_ms,
        interval_s=0.25,
    )


def response_has_resolved_todo_workspace(
    response: dict[str, Any],
    *,
    expected_root: Path,
) -> bool:
    actual_root = response.get("result", {}).get("values", {}).get("todo.workspace_root_path")
    if not actual_root:
        return False
    return Path(str(actual_root)).resolve() == expected_root


def extract_snapshot_tab(snapshot_response: dict[str, Any], *, index: int = 0) -> dict[str, Any]:
    tabs = snapshot_response.get("result", {}).get("tabs") or []
    if len(tabs) <= index:
        raise RuntimeError(
            f"Expected at least {index + 1} tab(s), got {len(tabs)} in snapshot: "
            f"{json.dumps(snapshot_response, sort_keys=True)}"
        )
    return tabs[index]


def extract_primary_terminal(snapshot_response: dict[str, Any]) -> tuple[str, str]:
    tab = extract_snapshot_tab(snapshot_response, index=0)
    terminals = tab.get("terminals") or []
    if not terminals:
        raise RuntimeError(f"Primary tab has no terminals: {json.dumps(tab, sort_keys=True)}")
    return str(tab["tab_id"]), str(terminals[0]["terminal_id"])


def find_tab(snapshot_response: dict[str, Any], tab_id: str) -> dict[str, Any] | None:
    tabs = snapshot_response.get("result", {}).get("tabs") or []
    for tab in tabs:
        if str(tab.get("tab_id")) == tab_id:
            return tab
    return None


def wait_for_tab(client: HarnessClient, tab_id: str, *, timeout_ms: int) -> dict[str, Any]:
    return wait_until(
        f"tab {tab_id}",
        lambda: find_tab(client.request("state.snapshot", _label=f"wait-tab-{tab_id}"), tab_id),
        timeout_ms=timeout_ms,
    )


def wait_for_tab_absent(client: HarnessClient, tab_id: str, *, timeout_ms: int) -> dict[str, Any]:
    return wait_until(
        f"tab {tab_id} to disappear",
        lambda: client.request("state.snapshot", _label=f"wait-tab-absent-{tab_id}")
        if find_tab(client.request("state.snapshot", _label=f"wait-tab-absent-probe-{tab_id}"), tab_id) is None
        else None,
        timeout_ms=timeout_ms,
    )


def wait_for_terminal_absent(client: HarnessClient, terminal_id: str, *, timeout_ms: int) -> dict[str, Any]:
    def predicate() -> dict[str, Any] | None:
        snapshot = client.request("state.snapshot", _label=f"wait-terminal-absent-{terminal_id}")
        tabs = snapshot.get("result", {}).get("tabs") or []
        for tab in tabs:
            for terminal in tab.get("terminals") or []:
                if str(terminal.get("terminal_id")) == terminal_id:
                    return None
        return snapshot

    return wait_until(f"terminal {terminal_id} to disappear", predicate, timeout_ms=timeout_ms)


def wait_for_terminal_output(
    client: HarnessClient,
    *,
    terminal_id: str,
    write_id: str,
    marker: str,
    timeout_ms: int,
) -> dict[str, Any]:
    def predicate() -> dict[str, Any] | None:
        response = client.request(
            "terminal.read",
            _label=f"terminal.read.{write_id}",
            terminal_id=terminal_id,
            scope="screen",
            mode="snapshot",
            max_lines=200,
            max_chars=24000,
            read_after_write_id=write_id,
        )
        result = response.get("result", {})
        if result.get("observed_write_id") == write_id and marker in (result.get("content") or ""):
            return response
        return None

    return wait_until(
        f"terminal output for write {write_id}",
        predicate,
        timeout_ms=timeout_ms,
    )


def find_window(windows_response: dict[str, Any], *, kind: str | None = None, window_number: int | None = None) -> dict[str, Any] | None:
    windows = windows_response.get("result", {}).get("windows") or []
    for window in windows:
        if kind is not None and window.get("kind") != kind:
            continue
        if window_number is not None and int(window.get("window_number", -1)) != window_number:
            continue
        return window
    return None


def wait_for_window(
    client: HarnessClient,
    *,
    kind: str | None = None,
    window_number: int | None = None,
    predicate: Callable[[dict[str, Any]], bool] | None = None,
    timeout_ms: int,
    label: str,
) -> dict[str, Any]:
    def inner() -> dict[str, Any] | None:
        response = client.request("window.list", _label=label)
        window = find_window(response, kind=kind, window_number=window_number)
        if window is None:
            return None
        if predicate is not None and not predicate(window):
            return None
        return window

    return wait_until(f"window {kind or window_number}", inner, timeout_ms=timeout_ms)


def wait_for_panel_state(
    client: HarnessClient,
    panel_id: str,
    *,
    predicate: Callable[[dict[str, Any]], bool],
    timeout_ms: int,
    label: str,
) -> dict[str, Any]:
    def inner() -> dict[str, Any] | None:
        response = client.request("panel.state.get", _label=label, panel_id=panel_id)
        panels = response.get("result", {}).get("panels") or []
        panel = panels[0] if panels else None
        if panel and predicate(panel):
            return panel
        return None

    return wait_until(f"panel {panel_id}", inner, timeout_ms=timeout_ms)


def record_summary(artifact: dict[str, Any], key: str, value: Any) -> None:
    artifact.setdefault("summary", {})[key] = value


def record_compatibility_result(
    artifact: dict[str, Any],
    *,
    command: str,
    response: dict[str, Any],
    evidence: dict[str, Any],
) -> None:
    artifact.setdefault("compatibility_matrix", []).append(
        {
            "command": command,
            "status": response.get("status"),
            "request_id": response.get("request_id"),
            "evidence": evidence,
        }
    )


def run_acceptance(args: argparse.Namespace) -> dict[str, Any]:
    app_bundle = Path(args.app).resolve() if args.app else resolve_default_app()
    runtime_root = Path(args.runtime_root).resolve() if args.runtime_root else None
    output_path = Path(args.output).expanduser().resolve()

    session_root = Path(f"/tmp/ghx-control-harness-protocol-{uuid.uuid4().hex[:8]}")
    home_dir = session_root / "home"
    app_support_root = session_root / "app-support"
    todo_workspace_root = create_isolated_todo_workspace(session_root / "todo-workspace")
    config_path = home_dir / ".config" / "ghostty" / "config"
    log_path = session_root / "app.log"

    artifact: dict[str, Any] = {
        "app": str(app_bundle),
        "runtime_root": str(runtime_root) if runtime_root is not None else None,
        "session_root": str(session_root),
        "isolated_todo_workspace_root": str(todo_workspace_root),
        "log_path": str(log_path),
        "related_live_gates": [
            "scripts/control_harness_terminal_v2_live_acceptance.py",
            "scripts/control_harness_gateway_transport_live_acceptance.py",
            "scripts/control_harness_diagnostics_live_acceptance.py",
            "scripts/browser_context_protocol_acceptance.py",
            "scripts/browser_runtime_prompt_resolution_acceptance.py",
            "scripts/browser_cookie_persistence_acceptance.py",
            "scripts/browser_popup_event_acceptance.py",
            "scripts/browser_last_window_close_acceptance.py",
        ],
        "verified_command_families": [
            "system",
            "app",
            "state/tab/terminal-basic",
            "runtime",
            "todo",
            "window",
            "panel",
            "settings",
            "diagnostics",
            "events.stream",
        ],
    }

    proc: subprocess.Popen[str] | None = None
    current_pid: int | None = None
    current_socket: str | None = None
    relaunched = False
    client: HarnessClient | None = None
    skip_cleanup = False
    legacy_events_client: socket.socket | None = None

    try:
        proc = launch_app(
            app_bundle,
            log_path,
            runtime_root=runtime_root,
            app_support_root=app_support_root,
            home_dir=home_dir,
            config_path=config_path,
            todo_workspace_root=todo_workspace_root,
        )
        current_pid = proc.pid
        current_socket = wait_for_harness_socket(current_pid, timeout_ms=args.startup_timeout_ms)
        client = HarnessClient(current_socket, timeout=args.request_timeout, artifact=artifact)

        handshake = client.request("system.handshake")
        target = wait_for_expected_target_pid(
            client,
            expected_pid=current_pid,
            timeout_ms=args.startup_timeout_ms,
        )
        capabilities = client.request("system.capabilities.get")
        app_state = client.request("app.state.get")
        initial_snapshot = wait_until(
            "primary terminal snapshot",
            lambda: client.request("state.snapshot", _label="state.snapshot.initial")
            if (client.request("state.snapshot", _label="state.snapshot.initial.probe").get("result", {}).get("tabs") or [])
            else None,
            timeout_ms=args.startup_timeout_ms,
        )

        base_tab_id, base_terminal_id = extract_primary_terminal(initial_snapshot)
        current_pid = int(target["result"]["instance"]["process_id"])
        current_socket = str(target["result"]["instance"]["socket_path"])
        client.set_socket(current_socket)

        record_summary(
            artifact,
            "system",
            {
                "handshake_commands_contains": [
                    "system.capabilities.get",
                    "app.state.get",
                    "tab.new",
                    "runtime.snapshot",
                    "todo.snapshot",
                    "window.list",
                    "settings.apply",
                    "diagnostics.audit.query",
                ],
                "resolved_process_id": current_pid,
                "resolved_socket_path": current_socket,
                "feature_set": capabilities["result"]["features"],
                "initial_app_state": app_state["result"],
            },
        )

        rename_title = "Harness Live Base"
        client.request("tab.rename", tab_id=base_tab_id, title=rename_title)
        renamed_tab = wait_until(
            "renamed base tab",
            lambda: (
                tab
                if (tab := find_tab(client.request("state.snapshot", _label="state.snapshot.after-rename"), base_tab_id))
                and tab.get("title") == rename_title
                else None
            ),
            timeout_ms=args.settle_ms,
        )

        terminal_close_tab_response = client.request("tab.new", title="Harness Terminal Close")
        terminal_close_tab_id = str(terminal_close_tab_response["result"]["tab_id"])
        terminal_close_terminal_id = str(terminal_close_tab_response["result"]["terminal_id"])
        wait_for_tab(client, terminal_close_tab_id, timeout_ms=args.settle_ms)

        tab_close_response = client.request("tab.new", title="Harness Tab Close")
        tab_close_id = str(tab_close_response["result"]["tab_id"])
        tab_close_terminal_id = str(tab_close_response["result"]["terminal_id"])
        wait_for_tab(client, tab_close_id, timeout_ms=args.settle_ms)

        run_marker = f"RUN_{uuid.uuid4().hex[:8]}"
        run_response = client.request(
            "terminal.command.run",
            terminal_id=base_terminal_id,
            command_text=f"printf '{run_marker}\\n'",
        )
        run_write_id = str(run_response["result"]["write_id"])
        run_read = wait_for_terminal_output(
            client,
            terminal_id=base_terminal_id,
            write_id=run_write_id,
            marker=run_marker,
            timeout_ms=args.settle_ms,
        )

        write_marker = f"WRITE_{uuid.uuid4().hex[:8]}"
        write_response = client.request(
            "terminal.write",
            terminal_id=base_terminal_id,
            text=f"printf '{write_marker}\\n'",
        )
        write_write_id = str(write_response["result"]["write_id"])
        key_response = client.request(
            "terminal.key",
            terminal_id=base_terminal_id,
            terminal_key="enter",
        )
        key_write_id = str(key_response["result"]["write_id"])
        key_read = wait_for_terminal_output(
            client,
            terminal_id=base_terminal_id,
            write_id=key_write_id,
            marker=write_marker,
            timeout_ms=args.settle_ms,
        )

        close_terminal_response = client.request(
            "terminal.close",
            terminal_id=terminal_close_terminal_id,
        )
        wait_for_terminal_absent(client, terminal_close_terminal_id, timeout_ms=args.settle_ms)

        snapshot_after_terminal_close = client.request("state.snapshot", _label="state.snapshot.after-terminal-close")
        terminal_window_tab = wait_for_tab(client, base_tab_id, timeout_ms=args.settle_ms)
        terminal_window_number = int(terminal_window_tab["window_number"])

        client.request(
            "window.floatOnTop.set",
            window_number=terminal_window_number,
            payload={"enabled": "true"},
        )
        float_on = wait_for_window(
            client,
            window_number=terminal_window_number,
            predicate=lambda window: bool(window.get("is_floating_on_top")) is True,
            timeout_ms=args.settle_ms,
            label="window.list.float-on",
        )
        client.request(
            "window.floatOnTop.set",
            window_number=terminal_window_number,
            payload={"enabled": "false"},
        )
        float_off = wait_for_window(
            client,
            window_number=terminal_window_number,
            predicate=lambda window: bool(window.get("is_floating_on_top")) is False,
            timeout_ms=args.settle_ms,
            label="window.list.float-off",
        )

        client.request("window.tabOverview.toggle", window_number=terminal_window_number)
        overview_on = wait_for_window(
            client,
            window_number=terminal_window_number,
            predicate=lambda window: bool(window.get("tab_overview_visible")) is True,
            timeout_ms=args.settle_ms,
            label="window.list.tab-overview-on",
        )
        client.request("window.tabOverview.toggle", window_number=terminal_window_number)
        overview_off = wait_for_window(
            client,
            window_number=terminal_window_number,
            predicate=lambda window: bool(window.get("tab_overview_visible")) is False,
            timeout_ms=args.settle_ms,
            label="window.list.tab-overview-off",
        )

        panel_list = client.request("panel.list")
        client.request("panel.open", panel_id="settings", panel_tab_id="gateway")
        settings_panel_gateway = wait_for_panel_state(
            client,
            "settings",
            predicate=lambda panel: bool(panel.get("is_visible")) is True and panel.get("selected_tab_id") == "gateway",
            timeout_ms=args.settle_ms,
            label="panel.state.get.settings.gateway",
        )
        client.request("panel.focus", panel_id="settings", panel_tab_id="gateway")
        client.request("panel.tab.select", panel_id="settings", panel_tab_id="general")
        settings_panel_general = wait_for_panel_state(
            client,
            "settings",
            predicate=lambda panel: bool(panel.get("is_visible")) is True and panel.get("selected_tab_id") == "general",
            timeout_ms=args.settle_ms,
            label="panel.state.get.settings.general",
        )
        client.request("panel.open", panel_id="ssh_connections", panel_tab_id="browser")
        ssh_panel_browser = wait_for_panel_state(
            client,
            "ssh_connections",
            predicate=lambda panel: bool(panel.get("is_visible")) is True and panel.get("selected_tab_id") == "browser",
            timeout_ms=args.settle_ms,
            label="panel.state.get.ssh.browser",
        )
        client.request("panel.focus", panel_id="ssh_connections", panel_tab_id="browser")
        client.request("panel.close", panel_id="ssh_connections")
        ssh_panel_closed = wait_for_panel_state(
            client,
            "ssh_connections",
            predicate=lambda panel: bool(panel.get("is_visible")) is False,
            timeout_ms=args.settle_ms,
            label="panel.state.get.ssh.closed",
        )

        settings_window_number = int(settings_panel_general["window_number"])
        client.request("window.hide", window_number=settings_window_number)
        hidden_settings_window = wait_for_window(
            client,
            window_number=settings_window_number,
            predicate=lambda window: bool(window.get("is_visible")) is False,
            timeout_ms=args.settle_ms,
            label="window.list.settings.hidden",
        )
        client.request("window.show", window_number=settings_window_number)
        shown_settings_window = wait_for_window(
            client,
            window_number=settings_window_number,
            predicate=lambda window: bool(window.get("is_visible")) is True,
            timeout_ms=args.settle_ms,
            label="window.list.settings.shown",
        )
        focus_settings_window_response = client.request("window.focus", window_number=settings_window_number)
        focused_settings_window = wait_for_window(
            client,
            window_number=settings_window_number,
            predicate=lambda window: bool(window.get("is_visible")) is True and window.get("kind") == "settings",
            timeout_ms=args.settle_ms,
            label="window.list.settings.focused",
        )
        client.request("window.close", window_number=settings_window_number)
        settings_panel_closed = wait_for_panel_state(
            client,
            "settings",
            predicate=lambda panel: bool(panel.get("is_visible")) is False,
            timeout_ms=args.settle_ms,
            label="panel.state.get.settings.closed",
        )

        settings_schema = client.request("settings.schema.get")
        settings_values_before = client.request("settings.values.get")
        current_values = dict(settings_values_before["result"]["values"])
        current_todo_workspace_root = str(current_values["todo.workspace_root_path"])
        if Path(current_todo_workspace_root).resolve() != todo_workspace_root:
            raise RuntimeError(
                "Live acceptance is not using the isolated todo workspace. "
                f"expected={todo_workspace_root} actual={current_todo_workspace_root}"
            )
        current_gateway_port = str(current_values["gateway.listen_port"])
        validate_gateway_port = "9528" if current_gateway_port == "9527" else "9527"
        staged_gateway_port = "9531" if current_gateway_port in {"9527", "9528", "9530"} else "9530"
        applied_gateway_port = "9541" if current_gateway_port in {"9540", "9541"} else "9540"

        validate_response = client.request(
            "settings.validate",
            payload={
                "gateway.listen_port": validate_gateway_port,
                "runtime.enabled": "true",
            },
        )
        stage_response = client.request(
            "settings.values.set",
            payload={"gateway.listen_port": staged_gateway_port},
        )
        diff_response = client.request("settings.diff")
        staged_values_response = client.request("settings.values.get", _label="settings.values.get.staged")
        reset_draft_response = client.request(
            "settings.reset",
            payload={"target": "draft"},
        )
        reset_draft_values = client.request("settings.values.get", _label="settings.values.get.after-reset-draft")

        apply_response = client.request(
            "settings.apply",
            payload={
                "gateway.listen_port": applied_gateway_port,
                "runtime.enabled": "true",
                "todo.enabled": "true",
                "todo.workspace_root_path": str(todo_workspace_root),
            },
        )
        def wait_for_applied_settings_values() -> dict[str, Any] | None:
            response = client.request("settings.values.get", _label="settings.values.get.after-apply")
            values = response.get("result", {}).get("values", {})
            if values.get("gateway.listen_port") != applied_gateway_port:
                return None
            if values.get("runtime.enabled") != "true":
                return None
            if not response_has_resolved_todo_workspace(response, expected_root=todo_workspace_root):
                return None
            return response

        applied_values_response = wait_until(
            "applied settings values",
            wait_for_applied_settings_values,
            timeout_ms=args.settle_ms,
        )

        events_subscribe = client.request(
            "events.stream.subscribe",
            since_sequence=0,
            event_limit=200,
        )
        stream_id = str(events_subscribe["result"]["stream_id"])
        diagnostics_event_buffer_status_subscribed = wait_until(
            "event buffer subscription count",
            lambda: (
                response
                if (
                    response := client.request(
                        "diagnostics.eventBuffer.status",
                        _label="diagnostics.eventBuffer.status.subscribed",
                    )
                ).get("result", {}).get("status", {}).get("subscription_count", 0) >= 1
                else None
            ),
            timeout_ms=args.settle_ms,
        )

        client.request("panel.open", panel_id="settings", panel_tab_id="appearance")
        drained_events = wait_until(
            "drained buffered events",
            lambda: (
                response
                if (
                    response := client.request(
                        "events.stream.drain",
                        _label="events.stream.drain.initial",
                        stream_id=stream_id,
                        event_limit=50,
                    )
                ).get("result", {}).get("drained_event_count", 0) > 0
                else None
            ),
            timeout_ms=args.settle_ms,
        )
        events_unsubscribe = client.request(
            "events.stream.unsubscribe",
            stream_id=stream_id,
        )
        diagnostics_event_buffer_status_unsubscribed = client.request(
            "diagnostics.eventBuffer.status",
            _label="diagnostics.eventBuffer.status.unsubscribed",
        )

        runtime_snapshot_initial = client.request("runtime.snapshot")
        runtime_session_register = client.request(
            "runtime.session.register",
            terminal_id=base_terminal_id,
            workspace_id=base_tab_id,
            capabilities=["terminal"],
            lease_duration_seconds=15,
        )
        runtime_session_id = str(runtime_session_register["result"]["session"]["id"])
        runtime_session_heartbeat = client.request(
            "runtime.session.heartbeat",
            session_id=runtime_session_id,
            lease_duration_seconds=45,
        )
        runtime_task_enqueue_high = client.request(
            "runtime.task.enqueue",
            command_text="printf 'runtime claim\\n'",
            task_kind="terminal_command",
            priority=10,
            capabilities=["terminal"],
        )
        runtime_task_enqueue_low = client.request(
            "runtime.task.enqueue",
            command_text="printf 'runtime claim next\\n'",
            task_kind="terminal_command",
            priority=1,
            capabilities=["terminal"],
        )
        runtime_task_claim = client.request(
            "runtime.task.claim",
            session_id=runtime_session_id,
        )
        claimed_task_id = str(runtime_task_claim["result"]["task"]["id"])
        runtime_task_waiting = client.request(
            "runtime.task.update",
            session_id=runtime_session_id,
            task_id=claimed_task_id,
            task_state="waiting_approval",
        )
        runtime_task_approve = client.request(
            "runtime.task.approve",
            session_id=runtime_session_id,
            task_id=claimed_task_id,
        )
        runtime_task_cancel_approved = client.request(
            "runtime.task.cancel",
            session_id=runtime_session_id,
            task_id=claimed_task_id,
            reason="live_acceptance_advance",
        )
        runtime_task_claim_next = client.request(
            "runtime.task.claimNext",
            session_id=runtime_session_id,
        )
        claimed_next_task_id = str(runtime_task_claim_next["result"]["task"]["id"])
        runtime_task_running = client.request(
            "runtime.task.update",
            session_id=runtime_session_id,
            task_id=claimed_next_task_id,
            task_state="running",
        )
        runtime_task_cancel = client.request(
            "runtime.task.cancel",
            session_id=runtime_session_id,
            task_id=claimed_next_task_id,
            reason="live_acceptance_cleanup",
        )
        runtime_schedule_enqueue = client.request(
            "runtime.schedule.enqueue",
            command_text="printf 'scheduled live\\n'",
            task_kind="terminal_command",
            priority=3,
            capabilities=["terminal"],
            recurrence_mode="interval",
            interval_seconds=60,
            scheduled_at=iso8601_past(5),
        )
        runtime_schedule_id = str(runtime_schedule_enqueue["result"]["schedule"]["id"])
        runtime_schedule_update = client.request(
            "runtime.schedule.update",
            schedule_id=runtime_schedule_id,
            schedule_state="paused",
        )
        runtime_schedule_cancel = client.request(
            "runtime.schedule.cancel",
            schedule_id=runtime_schedule_id,
        )
        runtime_snapshot_final = client.request("runtime.snapshot", _label="runtime.snapshot.final")
        runtime_session_release = client.request(
            "runtime.session.release",
            session_id=runtime_session_id,
            reason="live_acceptance_complete",
        )

        today_string, yesterday_string = today_strings()
        todo_snapshot_initial = client.request("todo.snapshot", date=today_string, include_completed=True)
        if int(todo_snapshot_initial["result"]["returned_count"]) != 0:
            raise RuntimeError(
                "Isolated todo workspace was expected to start empty, "
                f"but returned_count={todo_snapshot_initial['result']['returned_count']}"
            )
        stale_add = client.request(
            "todo.add",
            title="Harness stale task",
            notes="carry forward me",
            date=yesterday_string,
        )
        today_add = client.request(
            "todo.add",
            title="Harness today task",
            notes="initial notes",
            date=today_string,
        )
        today_todo_id = str(today_add["result"]["mutated_todo_id"])
        todo_update = client.request(
            "todo.update",
            todo_id=today_todo_id,
            date=today_string,
            notes="updated in live acceptance",
        )
        todo_complete = client.request(
            "todo.complete",
            todo_id=today_todo_id,
            date=today_string,
            completed=True,
        )
        todo_assign = client.request(
            "todo.assign",
            todo_id=today_todo_id,
            date=today_string,
            workspace_id=base_tab_id,
        )
        todo_sync_stale = client.request(
            "todo.syncStale",
            date=today_string,
        )
        todo_snapshot_final = client.request(
            "todo.snapshot",
            date=today_string,
            include_completed=True,
            _label="todo.snapshot.final",
        )

        diagnostics_metrics_before_reset = client.request("diagnostics.metrics.get")
        diagnostics_logs_tail = client.request(
            "diagnostics.logs.tail",
            payload={"source": "audit"},
            max_lines=20,
        )
        diagnostics_audit_query = wait_until(
            "diagnostics audit query results",
            lambda: (
                response
                if (
                    response := client.request(
                        "diagnostics.audit.query",
                        _label="diagnostics.audit.query.settings-apply",
                        payload={"command": "settings.apply"},
                        max_lines=20,
                    )
                ).get("result", {}).get("records")
                else None
            ),
            timeout_ms=args.settle_ms,
        )
        diagnostics_errors_recent = client.request("diagnostics.errors.recent")
        diagnostics_metrics_reset = client.request("diagnostics.metrics.reset")

        client.request("panel.close", panel_id="settings")
        wait_for_panel_state(
            client,
            "settings",
            predicate=lambda panel: bool(panel.get("is_visible")) is False,
            timeout_ms=args.settle_ms,
            label="panel.state.get.settings.closed.final",
        )

        tab_close_result = client.request(
            "tab.close",
            tab_id=tab_close_id,
            force=True,
        )
        wait_for_tab_absent(client, tab_close_id, timeout_ms=args.settle_ms)

        reset_defaults_response = client.request(
            "settings.reset",
            payload={"target": "defaults"},
        )
        reset_default_values = dict(reset_defaults_response["result"]["values"])
        settings_values_after_defaults = wait_until(
            "default settings reset",
            lambda: (
                response
                if (
                    response := client.request(
                        "settings.values.get",
                        _label="settings.values.get.after-reset-defaults",
                    )
                ).get("result", {}).get("values") == reset_default_values
                and response.get("result", {}).get("staged_values") in (None, {})
                else None
            ),
            timeout_ms=args.settle_ms,
        )
        reapply_isolated_todo_response = client.request(
            "settings.apply",
            payload={
                "todo.enabled": "true",
                "todo.workspace_root_path": str(todo_workspace_root),
            },
        )
        def wait_for_reisolated_todo_workspace() -> dict[str, Any] | None:
            response = client.request(
                "settings.values.get",
                _label="settings.values.get.after-todo-reisolation",
            )
            values = response.get("result", {}).get("values", {})
            if values.get("todo.enabled") != "true":
                return None
            if not response_has_resolved_todo_workspace(response, expected_root=todo_workspace_root):
                return None
            return response

        settings_values_after_todo_reisolation = wait_until(
            "isolated todo workspace reapply",
            wait_for_reisolated_todo_workspace,
            timeout_ms=args.settle_ms,
        )

        relaunch_response = client.request("app.relaunch")
        old_pid = current_pid
        post_relaunch_target = wait_until(
            "app relaunch",
            lambda: (
                response
                if (
                    response := client.request("system.target.resolve", _label="system.target.resolve.after-relaunch")
                ).get("result", {}).get("instance", {}).get("process_id") not in {None, old_pid}
                else None
            ),
            timeout_ms=max(args.settle_ms, 20000),
            interval_s=0.5,
        )
        current_pid = int(post_relaunch_target["result"]["instance"]["process_id"])
        current_socket = str(post_relaunch_target["result"]["instance"]["socket_path"])
        client.set_socket(current_socket)
        relaunched = True
        post_relaunch_snapshot = wait_until(
            "post-relaunch snapshot",
            lambda: (
                response
                if (response := client.request("state.snapshot", _label="state.snapshot.after-relaunch")).get("result", {}).get("tabs")
                else None
            ),
            timeout_ms=args.settle_ms,
        )
        settings_values_after_relaunch = client.request(
            "settings.values.get",
            _label="settings.values.get.after-relaunch",
        )
        relaunch_todo_workspace_root = (
            settings_values_after_relaunch.get("result", {})
            .get("values", {})
            .get("todo.workspace_root_path", "")
        )
        if not response_has_resolved_todo_workspace(
            settings_values_after_relaunch,
            expected_root=todo_workspace_root,
        ):
            raise RuntimeError(
                "Relaunched compatibility phase lost the isolated todo workspace. "
                f"expected={todo_workspace_root} actual={relaunch_todo_workspace_root}"
            )

        compatibility_expected_commands = {
            "handshake",
            "snapshot",
            "workspace.snapshot",
            "workspace.tab.snapshot",
            "new-tab",
            "workspace.tab.create",
            "rename-tab",
            "send-text",
            "terminal.input.send",
            "send-key",
            "run-command",
            "terminal.run",
            "read-terminal",
            "terminal.output.read",
            "close-terminal",
            "terminal.session.close",
            "close-tab",
            "workspace.tab.close",
            "terminal.snapshot.v2",
            "terminal.semantic.v2",
            "agent.runtime.snapshot",
            "agent.runtime.session.register",
            "agent.runtime.session.heartbeat",
            "agent.runtime.session.release",
            "agent.runtime.task.enqueue",
            "agent.runtime.task.claim",
            "agent.runtime.task.claim_next",
            "runtime.task.claim_next",
            "agent.runtime.task.update",
            "agent.runtime.task.approve",
            "agent.runtime.task.cancel",
            "agent.runtime.schedule.enqueue",
            "agent.runtime.schedule.update",
            "agent.runtime.schedule.cancel",
            "todo-snapshot",
            "todo.item.list",
            "todo-add",
            "todo.item.create",
            "todo-update",
            "todo.item.update",
            "todo-complete",
            "todo.item.complete",
            "todo-assign",
            "todo.item.assign",
            "todo-sync-stale",
            "todo.item.sync_stale",
            "events.subscribe",
        }

        compatibility_base_tab_id, compatibility_base_terminal_id = extract_primary_terminal(post_relaunch_snapshot)

        legacy_handshake = client.request("handshake", _label="compat.handshake")
        if legacy_handshake.get("result", {}).get("compatibility", {}).get("authority") != "control_harness":
            raise RuntimeError("handshake compatibility metadata did not expose control_harness authority")
        record_compatibility_result(
            artifact,
            command="handshake",
            response=legacy_handshake,
            evidence={
                "authority": legacy_handshake["result"]["compatibility"]["authority"],
                "legacy_commands": legacy_handshake["result"]["compatibility"]["legacy_commands"],
            },
        )

        for snapshot_command in ("snapshot", "workspace.snapshot", "workspace.tab.snapshot"):
            snapshot_response = client.request(snapshot_command, _label=f"compat.{snapshot_command}")
            snapshot_tab = find_tab(snapshot_response, compatibility_base_tab_id)
            if snapshot_tab is None:
                raise RuntimeError(f"{snapshot_command} did not return the live base tab")
            record_compatibility_result(
                artifact,
                command=snapshot_command,
                response=snapshot_response,
                evidence={
                    "tab_id": compatibility_base_tab_id,
                    "tab_count": len(snapshot_response["result"]["tabs"]),
                },
            )

        legacy_new_tab = client.request("new-tab", _label="compat.new-tab", title="Compat Legacy Tab")
        legacy_new_tab_id = str(legacy_new_tab["result"]["tab_id"])
        wait_for_tab(client, legacy_new_tab_id, timeout_ms=args.settle_ms)
        record_compatibility_result(
            artifact,
            command="new-tab",
            response=legacy_new_tab,
            evidence={
                "tab_id": legacy_new_tab_id,
                "terminal_id": legacy_new_tab["result"]["terminal_id"],
            },
        )

        workspace_create_tab = client.request(
            "workspace.tab.create",
            _label="compat.workspace.tab.create",
            title="Compat Workspace Create",
        )
        workspace_create_tab_id = str(workspace_create_tab["result"]["tab_id"])
        wait_for_tab(client, workspace_create_tab_id, timeout_ms=args.settle_ms)
        record_compatibility_result(
            artifact,
            command="workspace.tab.create",
            response=workspace_create_tab,
            evidence={
                "tab_id": workspace_create_tab_id,
                "terminal_id": workspace_create_tab["result"]["terminal_id"],
            },
        )

        close_terminal_setup = client.request("tab.new", _label="compat.setup.close-terminal", title="Compat Close Terminal")
        close_terminal_id = str(close_terminal_setup["result"]["terminal_id"])
        session_close_setup = client.request("tab.new", _label="compat.setup.session-close", title="Compat Session Close")
        session_close_terminal_id = str(session_close_setup["result"]["terminal_id"])

        rename_response = client.request(
            "rename-tab",
            _label="compat.rename-tab",
            tab_id=legacy_new_tab_id,
            title="Compat Renamed Tab",
        )
        renamed_compat_tab = wait_until(
            "compat renamed tab",
            lambda: (
                tab
                if (tab := find_tab(client.request("state.snapshot", _label="compat.state.snapshot.renamed"), legacy_new_tab_id))
                and tab.get("title") == "Compat Renamed Tab"
                else None
            ),
            timeout_ms=args.settle_ms,
        )
        record_compatibility_result(
            artifact,
            command="rename-tab",
            response=rename_response,
            evidence={
                "tab_id": legacy_new_tab_id,
                "title": renamed_compat_tab["title"],
            },
        )

        send_text_marker = f"COMPAT_SEND_TEXT_{uuid.uuid4().hex[:8]}"
        send_text_response = client.request(
            "send-text",
            _label="compat.send-text",
            terminal_id=compatibility_base_terminal_id,
            text=f"printf '{send_text_marker}\\n'",
        )
        send_key_response = client.request(
            "send-key",
            _label="compat.send-key",
            terminal_id=compatibility_base_terminal_id,
            terminal_key="enter",
        )
        send_text_read = wait_for_terminal_output(
            client,
            terminal_id=compatibility_base_terminal_id,
            write_id=str(send_key_response["result"]["write_id"]),
            marker=send_text_marker,
            timeout_ms=args.settle_ms,
        )
        record_compatibility_result(
            artifact,
            command="send-text",
            response=send_text_response,
            evidence={
                "marker": send_text_marker,
                "observed_write_id": send_text_read["result"]["observed_write_id"],
            },
        )
        record_compatibility_result(
            artifact,
            command="send-key",
            response=send_key_response,
            evidence={
                "marker": send_text_marker,
                "observed_write_id": send_text_read["result"]["observed_write_id"],
            },
        )

        input_send_marker = f"COMPAT_INPUT_SEND_{uuid.uuid4().hex[:8]}"
        terminal_input_send = client.request(
            "terminal.input.send",
            _label="compat.terminal.input.send",
            terminal_id=compatibility_base_terminal_id,
            text=f"printf '{input_send_marker}\\n'",
        )
        terminal_input_key = client.request(
            "terminal.key",
            _label="compat.terminal.input.send.enter",
            terminal_id=compatibility_base_terminal_id,
            terminal_key="enter",
        )
        terminal_input_read = wait_for_terminal_output(
            client,
            terminal_id=compatibility_base_terminal_id,
            write_id=str(terminal_input_key["result"]["write_id"]),
            marker=input_send_marker,
            timeout_ms=args.settle_ms,
        )
        record_compatibility_result(
            artifact,
            command="terminal.input.send",
            response=terminal_input_send,
            evidence={
                "marker": input_send_marker,
                "observed_write_id": terminal_input_read["result"]["observed_write_id"],
            },
        )

        run_command_marker = f"COMPAT_RUN_COMMAND_{uuid.uuid4().hex[:8]}"
        run_command_response = client.request(
            "run-command",
            _label="compat.run-command",
            terminal_id=compatibility_base_terminal_id,
            command_text=f"printf '{run_command_marker}\\n'",
        )
        run_command_read = wait_for_terminal_output(
            client,
            terminal_id=compatibility_base_terminal_id,
            write_id=str(run_command_response["result"]["write_id"]),
            marker=run_command_marker,
            timeout_ms=args.settle_ms,
        )
        record_compatibility_result(
            artifact,
            command="run-command",
            response=run_command_response,
            evidence={
                "marker": run_command_marker,
                "observed_write_id": run_command_read["result"]["observed_write_id"],
            },
        )

        terminal_run_marker = f"COMPAT_TERMINAL_RUN_{uuid.uuid4().hex[:8]}"
        terminal_run_response = client.request(
            "terminal.run",
            _label="compat.terminal.run",
            terminal_id=compatibility_base_terminal_id,
            command_text=f"printf '{terminal_run_marker}\\n'",
        )
        terminal_run_read = wait_for_terminal_output(
            client,
            terminal_id=compatibility_base_terminal_id,
            write_id=str(terminal_run_response["result"]["write_id"]),
            marker=terminal_run_marker,
            timeout_ms=args.settle_ms,
        )
        record_compatibility_result(
            artifact,
            command="terminal.run",
            response=terminal_run_response,
            evidence={
                "marker": terminal_run_marker,
                "observed_write_id": terminal_run_read["result"]["observed_write_id"],
            },
        )

        read_terminal_response = client.request(
            "read-terminal",
            _label="compat.read-terminal",
            terminal_id=compatibility_base_terminal_id,
            scope="screen",
            mode="snapshot",
            max_lines=200,
            max_chars=24000,
            read_after_write_id=str(run_command_response["result"]["write_id"]),
        )
        if run_command_marker not in (read_terminal_response["result"]["content"] or ""):
            raise RuntimeError("read-terminal did not return the run-command marker")
        record_compatibility_result(
            artifact,
            command="read-terminal",
            response=read_terminal_response,
            evidence={
                "marker": run_command_marker,
                "content_preview": read_terminal_response["result"]["content"][-160:],
            },
        )

        terminal_output_read = client.request(
            "terminal.output.read",
            _label="compat.terminal.output.read",
            terminal_id=compatibility_base_terminal_id,
            scope="screen",
            mode="snapshot",
            max_lines=200,
            max_chars=24000,
            read_after_write_id=str(terminal_input_key["result"]["write_id"]),
        )
        if input_send_marker not in (terminal_output_read["result"]["content"] or ""):
            raise RuntimeError("terminal.output.read did not return the terminal.input.send marker")
        record_compatibility_result(
            artifact,
            command="terminal.output.read",
            response=terminal_output_read,
            evidence={
                "marker": input_send_marker,
                "content_preview": terminal_output_read["result"]["content"][-160:],
            },
        )

        terminal_snapshot_v2 = client.request(
            "terminal.snapshot.v2",
            _label="compat.terminal.snapshot.v2",
            terminal_id=compatibility_base_terminal_id,
            max_lines=200,
            max_chars=24000,
        )
        if terminal_snapshot_v2["result"]["snapshot_format"] != "ansi_text":
            raise RuntimeError("terminal.snapshot.v2 did not return ansi_text")
        record_compatibility_result(
            artifact,
            command="terminal.snapshot.v2",
            response=terminal_snapshot_v2,
            evidence={
                "snapshot_format": terminal_snapshot_v2["result"]["snapshot_format"],
                "terminal_id": terminal_snapshot_v2["result"]["terminal_id"],
                "content_preview": (terminal_snapshot_v2["result"]["content"] or "")[-160:],
            },
        )

        terminal_semantic_v2 = client.request(
            "terminal.semantic.v2",
            _label="compat.terminal.semantic.v2",
            terminal_id=compatibility_base_terminal_id,
            max_lines=200,
            max_chars=24000,
        )
        logical_lines = terminal_semantic_v2["result"].get("logical_lines") or []
        if not isinstance(terminal_semantic_v2["result"].get("exact_text"), str) or not isinstance(logical_lines, list):
            raise RuntimeError("terminal.semantic.v2 did not return the expected semantic payload shape")
        record_compatibility_result(
            artifact,
            command="terminal.semantic.v2",
            response=terminal_semantic_v2,
            evidence={
                "terminal_id": terminal_semantic_v2["result"]["terminal_id"],
                "logical_line_count": len(logical_lines),
                "exact_text_length": len(terminal_semantic_v2["result"].get("exact_text") or ""),
            },
        )

        close_terminal_response = client.request(
            "close-terminal",
            _label="compat.close-terminal",
            terminal_id=close_terminal_id,
        )
        wait_for_terminal_absent(client, close_terminal_id, timeout_ms=args.settle_ms)
        record_compatibility_result(
            artifact,
            command="close-terminal",
            response=close_terminal_response,
            evidence={"terminal_id": close_terminal_id},
        )

        terminal_session_close = client.request(
            "terminal.session.close",
            _label="compat.terminal.session.close",
            terminal_id=session_close_terminal_id,
        )
        wait_for_terminal_absent(client, session_close_terminal_id, timeout_ms=args.settle_ms)
        record_compatibility_result(
            artifact,
            command="terminal.session.close",
            response=terminal_session_close,
            evidence={"terminal_id": session_close_terminal_id},
        )

        close_tab_response = client.request(
            "close-tab",
            _label="compat.close-tab",
            tab_id=legacy_new_tab_id,
            force=True,
        )
        wait_for_tab_absent(client, legacy_new_tab_id, timeout_ms=args.settle_ms)
        record_compatibility_result(
            artifact,
            command="close-tab",
            response=close_tab_response,
            evidence={"tab_id": legacy_new_tab_id},
        )

        workspace_close_tab_response = client.request(
            "workspace.tab.close",
            _label="compat.workspace.tab.close",
            tab_id=workspace_create_tab_id,
            force=True,
        )
        wait_for_tab_absent(client, workspace_create_tab_id, timeout_ms=args.settle_ms)
        record_compatibility_result(
            artifact,
            command="workspace.tab.close",
            response=workspace_close_tab_response,
            evidence={"tab_id": workspace_create_tab_id},
        )

        runtime_snapshot_compat = client.request("agent.runtime.snapshot", _label="compat.agent.runtime.snapshot")
        record_compatibility_result(
            artifact,
            command="agent.runtime.snapshot",
            response=runtime_snapshot_compat,
            evidence={
                "sessions": len(runtime_snapshot_compat["result"]["sessions"]),
                "tasks": len(runtime_snapshot_compat["result"]["tasks"]),
                "schedules": len(runtime_snapshot_compat["result"]["schedules"]),
            },
        )

        compat_runtime_register = client.request(
            "agent.runtime.session.register",
            _label="compat.agent.runtime.session.register",
            terminal_id=compatibility_base_terminal_id,
            workspace_id=compatibility_base_tab_id,
            capabilities=["terminal"],
            lease_duration_seconds=15,
        )
        compat_runtime_session_id = str(compat_runtime_register["result"]["session"]["id"])
        record_compatibility_result(
            artifact,
            command="agent.runtime.session.register",
            response=compat_runtime_register,
            evidence={"session_id": compat_runtime_session_id},
        )

        compat_runtime_heartbeat = client.request(
            "agent.runtime.session.heartbeat",
            _label="compat.agent.runtime.session.heartbeat",
            session_id=compat_runtime_session_id,
            lease_duration_seconds=45,
        )
        record_compatibility_result(
            artifact,
            command="agent.runtime.session.heartbeat",
            response=compat_runtime_heartbeat,
            evidence={"state": compat_runtime_heartbeat["result"]["session"]["state"]},
        )

        compat_task_high = client.request(
            "agent.runtime.task.enqueue",
            _label="compat.agent.runtime.task.enqueue.high",
            command_text="printf 'compat runtime high\\n'",
            task_kind="terminal_command",
            priority=10,
            capabilities=["terminal"],
        )
        compat_task_mid = client.request(
            "agent.runtime.task.enqueue",
            _label="compat.agent.runtime.task.enqueue.mid",
            command_text="printf 'compat runtime mid\\n'",
            task_kind="terminal_command",
            priority=5,
            capabilities=["terminal"],
        )
        compat_task_low = client.request(
            "agent.runtime.task.enqueue",
            _label="compat.agent.runtime.task.enqueue.low",
            command_text="printf 'compat runtime low\\n'",
            task_kind="terminal_command",
            priority=1,
            capabilities=["terminal"],
        )
        compat_enqueued_ids = [
            str(compat_task_high["result"]["task"]["id"]),
            str(compat_task_mid["result"]["task"]["id"]),
            str(compat_task_low["result"]["task"]["id"]),
        ]
        record_compatibility_result(
            artifact,
            command="agent.runtime.task.enqueue",
            response=compat_task_low,
            evidence={"task_ids": compat_enqueued_ids},
        )

        compat_task_claim = client.request(
            "agent.runtime.task.claim",
            _label="compat.agent.runtime.task.claim",
            session_id=compat_runtime_session_id,
        )
        compat_claimed_task_id = str(compat_task_claim["result"]["task"]["id"])
        record_compatibility_result(
            artifact,
            command="agent.runtime.task.claim",
            response=compat_task_claim,
            evidence={"task_id": compat_claimed_task_id},
        )

        compat_task_update = client.request(
            "agent.runtime.task.update",
            _label="compat.agent.runtime.task.update",
            session_id=compat_runtime_session_id,
            task_id=compat_claimed_task_id,
            task_state="waiting_approval",
        )
        record_compatibility_result(
            artifact,
            command="agent.runtime.task.update",
            response=compat_task_update,
            evidence={"task_state": compat_task_update["result"]["task"]["state"]},
        )

        compat_task_approve = client.request(
            "agent.runtime.task.approve",
            _label="compat.agent.runtime.task.approve",
            session_id=compat_runtime_session_id,
            task_id=compat_claimed_task_id,
        )
        record_compatibility_result(
            artifact,
            command="agent.runtime.task.approve",
            response=compat_task_approve,
            evidence={"task_state": compat_task_approve["result"]["task"]["state"]},
        )

        compat_task_cancel = client.request(
            "agent.runtime.task.cancel",
            _label="compat.agent.runtime.task.cancel.first",
            session_id=compat_runtime_session_id,
            task_id=compat_claimed_task_id,
            reason="compatibility_matrix_cleanup",
        )
        record_compatibility_result(
            artifact,
            command="agent.runtime.task.cancel",
            response=compat_task_cancel,
            evidence={"task_state": compat_task_cancel["result"]["task"]["state"]},
        )

        compat_claim_next = client.request(
            "agent.runtime.task.claim_next",
            _label="compat.agent.runtime.task.claim_next",
            session_id=compat_runtime_session_id,
        )
        compat_claim_next_id = str(compat_claim_next["result"]["task"]["id"])
        record_compatibility_result(
            artifact,
            command="agent.runtime.task.claim_next",
            response=compat_claim_next,
            evidence={"task_id": compat_claim_next_id},
        )

        compat_claim_next_update = client.request(
            "agent.runtime.task.update",
            _label="compat.agent.runtime.task.update.claim-next",
            session_id=compat_runtime_session_id,
            task_id=compat_claim_next_id,
            task_state="running",
        )
        compat_claim_next_cancel = client.request(
            "agent.runtime.task.cancel",
            _label="compat.agent.runtime.task.cancel.second",
            session_id=compat_runtime_session_id,
            task_id=compat_claim_next_id,
            reason="compatibility_matrix_cleanup",
        )

        compat_runtime_claim_next = client.request(
            "runtime.task.claim_next",
            _label="compat.runtime.task.claim_next",
            session_id=compat_runtime_session_id,
        )
        compat_runtime_claim_next_id = str(compat_runtime_claim_next["result"]["task"]["id"])
        record_compatibility_result(
            artifact,
            command="runtime.task.claim_next",
            response=compat_runtime_claim_next,
            evidence={"task_id": compat_runtime_claim_next_id},
        )

        client.request(
            "agent.runtime.task.update",
            _label="compat.agent.runtime.task.update.runtime-claim-next",
            session_id=compat_runtime_session_id,
            task_id=compat_runtime_claim_next_id,
            task_state="running",
        )
        client.request(
            "agent.runtime.task.cancel",
            _label="compat.agent.runtime.task.cancel.third",
            session_id=compat_runtime_session_id,
            task_id=compat_runtime_claim_next_id,
            reason="compatibility_matrix_cleanup",
        )

        compat_schedule_enqueue = client.request(
            "agent.runtime.schedule.enqueue",
            _label="compat.agent.runtime.schedule.enqueue",
            command_text="printf 'compat schedule\\n'",
            task_kind="terminal_command",
            priority=2,
            capabilities=["terminal"],
            recurrence_mode="interval",
            interval_seconds=60,
            scheduled_at=iso8601_past(5),
        )
        compat_schedule_id = str(compat_schedule_enqueue["result"]["schedule"]["id"])
        record_compatibility_result(
            artifact,
            command="agent.runtime.schedule.enqueue",
            response=compat_schedule_enqueue,
            evidence={"schedule_id": compat_schedule_id},
        )

        compat_schedule_update = client.request(
            "agent.runtime.schedule.update",
            _label="compat.agent.runtime.schedule.update",
            schedule_id=compat_schedule_id,
            schedule_state="paused",
        )
        record_compatibility_result(
            artifact,
            command="agent.runtime.schedule.update",
            response=compat_schedule_update,
            evidence={"schedule_state": compat_schedule_update["result"]["schedule"]["state"]},
        )

        compat_schedule_cancel = client.request(
            "agent.runtime.schedule.cancel",
            _label="compat.agent.runtime.schedule.cancel",
            schedule_id=compat_schedule_id,
        )
        record_compatibility_result(
            artifact,
            command="agent.runtime.schedule.cancel",
            response=compat_schedule_cancel,
            evidence={"schedule_state": compat_schedule_cancel["result"]["schedule"]["state"]},
        )

        compat_runtime_release = client.request(
            "agent.runtime.session.release",
            _label="compat.agent.runtime.session.release",
            session_id=compat_runtime_session_id,
            reason="compatibility_matrix_complete",
        )
        record_compatibility_result(
            artifact,
            command="agent.runtime.session.release",
            response=compat_runtime_release,
            evidence={"state": compat_runtime_release["result"]["session"]["state"]},
        )

        compat_todo_snapshot = client.request(
            "todo-snapshot",
            _label="compat.todo-snapshot",
            date=today_string,
            include_completed=True,
        )
        if int(compat_todo_snapshot["result"]["returned_count"]) != int(
            todo_snapshot_final["result"]["returned_count"]
        ):
            raise RuntimeError(
                "Compatibility todo snapshot did not stay on the isolated workspace. "
                f"expected_count={todo_snapshot_final['result']['returned_count']} "
                f"actual_count={compat_todo_snapshot['result']['returned_count']}"
            )
        record_compatibility_result(
            artifact,
            command="todo-snapshot",
            response=compat_todo_snapshot,
            evidence={"returned_count": compat_todo_snapshot["result"]["returned_count"]},
        )

        compat_todo_add = client.request(
            "todo-add",
            _label="compat.todo-add",
            title="Compat todo add",
            notes="todo-add",
            date=today_string,
        )
        compat_todo_add_id = str(compat_todo_add["result"]["mutated_todo_id"])
        record_compatibility_result(
            artifact,
            command="todo-add",
            response=compat_todo_add,
            evidence={"todo_id": compat_todo_add_id},
        )

        compat_todo_item_create = client.request(
            "todo.item.create",
            _label="compat.todo.item.create",
            title="Compat todo item create",
            notes="todo.item.create",
            date=today_string,
        )
        compat_todo_item_create_id = str(compat_todo_item_create["result"]["mutated_todo_id"])
        record_compatibility_result(
            artifact,
            command="todo.item.create",
            response=compat_todo_item_create,
            evidence={"todo_id": compat_todo_item_create_id},
        )

        compat_todo_update = client.request(
            "todo-update",
            _label="compat.todo-update",
            todo_id=compat_todo_add_id,
            date=today_string,
            notes="todo-update applied",
        )
        record_compatibility_result(
            artifact,
            command="todo-update",
            response=compat_todo_update,
            evidence={"operation": compat_todo_update["result"]["operation"]},
        )

        compat_todo_item_update = client.request(
            "todo.item.update",
            _label="compat.todo.item.update",
            todo_id=compat_todo_item_create_id,
            date=today_string,
            notes="todo.item.update applied",
        )
        record_compatibility_result(
            artifact,
            command="todo.item.update",
            response=compat_todo_item_update,
            evidence={"operation": compat_todo_item_update["result"]["operation"]},
        )

        compat_todo_complete = client.request(
            "todo-complete",
            _label="compat.todo-complete",
            todo_id=compat_todo_add_id,
            date=today_string,
            completed=True,
        )
        record_compatibility_result(
            artifact,
            command="todo-complete",
            response=compat_todo_complete,
            evidence={"operation": compat_todo_complete["result"]["operation"]},
        )

        compat_todo_item_complete = client.request(
            "todo.item.complete",
            _label="compat.todo.item.complete",
            todo_id=compat_todo_item_create_id,
            date=today_string,
            completed=True,
        )
        record_compatibility_result(
            artifact,
            command="todo.item.complete",
            response=compat_todo_item_complete,
            evidence={"operation": compat_todo_item_complete["result"]["operation"]},
        )

        compat_todo_assign = client.request(
            "todo-assign",
            _label="compat.todo-assign",
            todo_id=compat_todo_add_id,
            date=today_string,
            workspace_id=compatibility_base_tab_id,
        )
        record_compatibility_result(
            artifact,
            command="todo-assign",
            response=compat_todo_assign,
            evidence={"operation": compat_todo_assign["result"]["operation"]},
        )

        compat_todo_item_assign = client.request(
            "todo.item.assign",
            _label="compat.todo.item.assign",
            todo_id=compat_todo_item_create_id,
            date=today_string,
            workspace_id=compatibility_base_tab_id,
        )
        record_compatibility_result(
            artifact,
            command="todo.item.assign",
            response=compat_todo_item_assign,
            evidence={"operation": compat_todo_item_assign["result"]["operation"]},
        )

        compat_stale_todo = client.request(
            "todo-add",
            _label="compat.todo-sync-stale.seed",
            title="Compat stale todo",
            notes="sync raw",
            date=yesterday_string,
        )
        compat_todo_sync = client.request(
            "todo-sync-stale",
            _label="compat.todo-sync-stale",
            date=today_string,
        )
        if int(compat_todo_sync["result"]["synced_count"]) < 1:
            raise RuntimeError("todo-sync-stale did not migrate any stale todos")
        record_compatibility_result(
            artifact,
            command="todo-sync-stale",
            response=compat_todo_sync,
            evidence={
                "seed_todo_id": compat_stale_todo["result"]["mutated_todo_id"],
                "synced_count": compat_todo_sync["result"]["synced_count"],
            },
        )

        compat_stale_todo_item = client.request(
            "todo.item.create",
            _label="compat.todo.item.sync_stale.seed",
            title="Compat stale todo item",
            notes="sync item",
            date=yesterday_string,
        )
        compat_todo_item_sync = client.request(
            "todo.item.sync_stale",
            _label="compat.todo.item.sync_stale",
            date=today_string,
        )
        if int(compat_todo_item_sync["result"]["synced_count"]) < 1:
            raise RuntimeError("todo.item.sync_stale did not migrate any stale todos")
        record_compatibility_result(
            artifact,
            command="todo.item.sync_stale",
            response=compat_todo_item_sync,
            evidence={
                "seed_todo_id": compat_stale_todo_item["result"]["mutated_todo_id"],
                "synced_count": compat_todo_item_sync["result"]["synced_count"],
            },
        )

        compat_todo_item_list = client.request(
            "todo.item.list",
            _label="compat.todo.item.list",
            date=today_string,
            include_completed=True,
        )
        compat_todo_item_entries = (
            compat_todo_item_list["result"].get("items")
            or compat_todo_item_list["result"].get("todos")
            or []
        )
        compat_todo_ids = {
            str(todo.get("todo_id"))
            for todo in compat_todo_item_entries
        }
        if compat_todo_add_id not in compat_todo_ids or compat_todo_item_create_id not in compat_todo_ids:
            raise RuntimeError("todo.item.list did not return the compatibility todo IDs")
        record_compatibility_result(
            artifact,
            command="todo.item.list",
            response=compat_todo_item_list,
            evidence={"returned_count": compat_todo_item_list["result"]["returned_count"]},
        )

        compat_event_seed = client.request(
            "terminal.command.run",
            _label="compat.events.subscribe.seed",
            terminal_id=compatibility_base_terminal_id,
            command_text=f"printf 'COMPAT_EVENT_REPLAY_{uuid.uuid4().hex[:8]}\\n'",
        )
        legacy_events_request = {
            "request_id": f"req-{uuid.uuid4().hex[:12]}",
            "command": "events.subscribe",
            "since_sequence": max(0, int(compat_event_seed["result"]["sequence"]) - 1),
            "event_limit": 8,
        }
        legacy_events_client, legacy_events_reader, legacy_events_ack = open_line_subscription(
            current_socket,
            legacy_events_request,
            timeout=args.request_timeout,
        )
        if legacy_events_ack.get("status") != "ok":
            raise RuntimeError(f"events.subscribe failed: {json.dumps(legacy_events_ack, sort_keys=True)}")
        compat_event_replay = wait_for_event_line(
            legacy_events_reader,
            timeout_ms=args.settle_ms,
            predicate=lambda record: record.get("request_id") == compat_event_seed["request_id"],
        )
        compat_event_live_command = client.request(
            "terminal.command.run",
            _label="compat.events.subscribe.live",
            terminal_id=compatibility_base_terminal_id,
            command_text=f"printf 'COMPAT_EVENT_LIVE_{uuid.uuid4().hex[:8]}\\n'",
        )
        compat_event_live = wait_for_event_line(
            legacy_events_reader,
            timeout_ms=args.settle_ms,
            predicate=lambda record: record.get("request_id") == compat_event_live_command["request_id"],
        )
        record_compatibility_result(
            artifact,
            command="events.subscribe",
            response=legacy_events_ack,
            evidence={
                "subscription_request_id": legacy_events_request["request_id"],
                "replay_request_id": compat_event_replay["request_id"],
                "live_request_id": compat_event_live["request_id"],
            },
        )
        legacy_events_client.close()
        legacy_events_client = None

        compatibility_actual_commands = {
            entry["command"] for entry in artifact.get("compatibility_matrix", [])
        }
        if compatibility_actual_commands != compatibility_expected_commands:
            missing = sorted(compatibility_expected_commands - compatibility_actual_commands)
            extra = sorted(compatibility_actual_commands - compatibility_expected_commands)
            raise RuntimeError(
                "compatibility matrix coverage mismatch: "
                f"missing={missing} extra={extra}"
            )

        record_summary(
            artifact,
            "tab_terminal",
            {
                "base_tab": renamed_tab,
                "run_marker": run_marker,
                "run_read_observed_write_id": run_read["result"]["observed_write_id"],
                "write_marker": write_marker,
                "write_read_observed_write_id": key_read["result"]["observed_write_id"],
                "closed_terminal_id": close_terminal_response["result"]["terminal_id"],
                "snapshot_after_terminal_close_tabs": len(snapshot_after_terminal_close["result"]["tabs"]),
                "closed_tab_id": tab_close_result["result"]["tab_id"],
            },
        )
        record_summary(
            artifact,
            "window_panel",
            {
                "terminal_window_number": terminal_window_number,
                "float_on_top_true": float_on["is_floating_on_top"],
                "float_on_top_false": float_off["is_floating_on_top"],
                "tab_overview_true": overview_on["tab_overview_visible"],
                "tab_overview_false": overview_off["tab_overview_visible"],
                "settings_hidden_visible": hidden_settings_window["is_visible"],
                "settings_shown_visible": shown_settings_window["is_visible"],
                "settings_focus_acknowledged": focus_settings_window_response["status"] == "ok",
                "settings_focused": focused_settings_window["is_focused"],
                "settings_panel_closed": settings_panel_closed["is_visible"],
                "ssh_panel_closed": ssh_panel_closed["is_visible"],
                "panel_list": panel_list["result"]["panels"],
            },
        )
        record_summary(
            artifact,
            "settings_events",
            {
                "schema_entry_count": len(settings_schema["result"]["entries"]),
                "isolated_todo_workspace_root": str(todo_workspace_root),
                "values_before": settings_values_before["result"]["values"],
                "validate_changed_keys": validate_response["result"]["changed_keys"],
                "draft_changed_keys": stage_response["result"]["changed_keys"],
                "diff_entries": diff_response["result"]["entries"],
                "staged_values": staged_values_response["result"]["staged_values"],
                "reset_draft_changed_keys": reset_draft_response["result"]["changed_keys"],
                "values_after_reset_draft": reset_draft_values["result"],
                "apply_changed_keys": apply_response["result"]["changed_keys"],
                "values_after_apply": applied_values_response["result"]["values"],
                "events_stream_id": stream_id,
                "drained_event_count": drained_events["result"]["drained_event_count"],
                "event_buffer_subscribed": diagnostics_event_buffer_status_subscribed["result"]["status"],
                "event_buffer_unsubscribed": diagnostics_event_buffer_status_unsubscribed["result"]["status"],
                "events_unsubscribed": events_unsubscribe["result"]["unsubscribed"],
                "reset_defaults_changed_keys": reset_defaults_response["result"]["changed_keys"],
                "values_after_defaults": settings_values_after_defaults["result"]["values"],
                "todo_reisolation_changed_keys": reapply_isolated_todo_response["result"]["changed_keys"],
                "values_after_todo_reisolation": settings_values_after_todo_reisolation["result"]["values"],
                "values_after_relaunch": settings_values_after_relaunch["result"]["values"],
            },
        )
        record_summary(
            artifact,
            "runtime",
            {
                "snapshot_initial_enabled": runtime_snapshot_initial["result"]["settings"]["enabled"],
                "session_id": runtime_session_id,
                "heartbeat_session_state": runtime_session_heartbeat["result"]["session"]["state"],
                "claim_task_id": claimed_task_id,
                "claim_task_state": runtime_task_claim["result"]["task"]["state"],
                "waiting_state": runtime_task_waiting["result"]["task"]["state"],
                "approved_state": runtime_task_approve["result"]["task"]["state"],
                "approved_cancelled_state": runtime_task_cancel_approved["result"]["task"]["state"],
                "claim_next_task_id": claimed_next_task_id,
                "claim_next_state": runtime_task_claim_next["result"]["task"]["state"],
                "running_state": runtime_task_running["result"]["task"]["state"],
                "cancelled_state": runtime_task_cancel["result"]["task"]["state"],
                "schedule_id": runtime_schedule_id,
                "schedule_paused_state": runtime_schedule_update["result"]["schedule"]["state"],
                "schedule_cancelled_state": runtime_schedule_cancel["result"]["schedule"]["state"],
                "snapshot_final_sessions": len(runtime_snapshot_final["result"]["sessions"]),
                "snapshot_final_tasks": len(runtime_snapshot_final["result"]["tasks"]),
                "snapshot_final_schedules": len(runtime_snapshot_final["result"]["schedules"]),
                "released_session_state": runtime_session_release["result"]["session"]["state"],
            },
        )
        record_summary(
            artifact,
            "todo_diagnostics_relaunch",
            {
                "todo_initial_count": todo_snapshot_initial["result"]["returned_count"],
                "stale_todo_id": stale_add["result"]["mutated_todo_id"],
                "today_todo_id": today_todo_id,
                "todo_update_operation": todo_update["result"]["operation"],
                "todo_complete_operation": todo_complete["result"]["operation"],
                "todo_assign_operation": todo_assign["result"]["operation"],
                "todo_sync_synced_count": todo_sync_stale["result"]["synced_count"],
                "todo_final_total_count": todo_snapshot_final["result"]["total_count"],
                "todo_final_returned_count": todo_snapshot_final["result"]["returned_count"],
                "metrics_before_reset": diagnostics_metrics_before_reset["result"]["metrics"],
                "logs_tail_line_count": len(diagnostics_logs_tail["result"]["lines"]),
                "audit_query_count": len(diagnostics_audit_query["result"]["records"]),
                "recent_error_count": len(diagnostics_errors_recent["result"]["errors"]),
                "metrics_after_reset": diagnostics_metrics_reset["result"]["metrics"],
                "relaunch_previous_pid": old_pid,
                "relaunch_current_pid": current_pid,
                "relaunch_snapshot_tab_count": len(post_relaunch_snapshot["result"]["tabs"]),
                "relaunch_app_state": relaunch_response["result"],
            },
        )
        record_summary(
            artifact,
            "compatibility_aliases",
            {
                "command_count": len(artifact.get("compatibility_matrix", [])),
                "commands": [entry["command"] for entry in artifact.get("compatibility_matrix", [])],
                "claim_next_update_state": compat_claim_next_update["result"]["task"]["state"],
                "claim_next_cancel_state": compat_claim_next_cancel["result"]["task"]["state"],
            },
        )

        if not args.skip_related_diagnostics_gate:
            related_diagnostics_output = (
                session_root / "related-control-harness-diagnostics-live-acceptance.json"
            )
            artifact.setdefault("related_gate_results", {})["diagnostics"] = run_related_gate(
                "control_harness_diagnostics_live_acceptance.py",
                app_bundle=app_bundle,
                output_path=related_diagnostics_output,
                startup_timeout_ms=args.startup_timeout_ms,
                request_timeout=args.request_timeout,
                settle_ms=args.settle_ms,
            )

        artifact["status"] = "ok"
        artifact["completed_at"] = iso8601_now()
        write_artifact(output_path, artifact)
        return artifact
    except Exception as exc:
        artifact["status"] = "error"
        artifact["completed_at"] = iso8601_now()
        artifact["error"] = str(exc)
        artifact["failure"] = {
            "current_pid": current_pid,
            "process_alive": pid_is_alive(current_pid),
            "process_snapshot": process_snapshot(current_pid),
            "proc_poll": proc.poll() if proc is not None else None,
            "current_socket": current_socket,
            "socket_exists": Path(current_socket).exists() if current_socket else False,
            "last_request_label": artifact.get("last_request_label"),
            "last_request_command": artifact.get("last_request_command"),
            "last_successful_request_label": artifact.get("last_successful_request_label"),
            "last_successful_request_command": artifact.get("last_successful_request_command"),
            "log_tail": tail_text(log_path),
            "session_root": str(session_root),
        }
        if args.keep_failed_session:
            artifact["failure"]["cleanup_skipped"] = True
            skip_cleanup = True
        write_artifact(output_path, artifact)
        raise
    finally:
        try:
            if legacy_events_client is not None:
                legacy_events_client.close()
        except OSError:
            pass
        try:
            if not skip_cleanup and current_pid is not None:
                if relaunched:
                    terminate_pid(current_pid)
                elif proc is not None:
                    terminate_process(proc)
        except Exception as exc:  # noqa: BLE001
            artifact["cleanup_error"] = str(exc)
            write_artifact(output_path, artifact)


def main() -> None:
    args = parse_args()
    artifact = run_acceptance(args)
    print(json.dumps(artifact, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
