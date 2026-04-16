#!/usr/bin/env python3

"""
Control Harness diagnostics governance live acceptance harness.

This script launches an isolated GhoDex app, talks to the real Control Harness
 socket, and proves the diagnostics governance commands added in the current
 implementation:

- diagnostics.status
- diagnostics.logs.query
- diagnostics.crash.latest
- diagnostics.mode.get / diagnostics.mode.set
- diagnostics.retention.get / diagnostics.retention.apply
- diagnostics.cleanup.run
- diagnostics.export.bundle
"""

from __future__ import annotations

import argparse
import json
import os
import plistlib
import re
import shutil
import socket
import subprocess
import time
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Callable


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = "/tmp/ghx-control-harness-diagnostics-live-acceptance.json"
HARNESS_SOCKET_RE = re.compile(r"(?P<path>/Users/.*/ControlHarness/harness\.sock)$")


def resolve_default_app() -> Path:
    candidates = [
        REPO_ROOT / "macos" / "build" / "ReleaseLocal" / "GhoDex.app",
        REPO_ROOT / "macos" / "build" / "Debug" / "GhoDex.app",
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate

    derived_data_root = Path.home() / "Library" / "Developer" / "Xcode" / "DerivedData"
    derived_matches = sorted(derived_data_root.glob("GhoDex-*/Build/Products/Debug/GhoDex.app"))
    if derived_matches:
        return derived_matches[-1]

    raise SystemExit(
        "No built GhoDex.app found under macos/build or Xcode DerivedData. "
        "Pass --app=/path/to/GhoDex.app."
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Prove diagnostics governance commands against a live GhoDex app."
    )
    parser.add_argument("--app", default=None, help="Path to the GhoDex.app bundle to launch.")
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
        help="Preserve the launched app/session root on failure for post-mortem inspection.",
    )
    return parser.parse_args()


def iso8601_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def iso8601_past(days: int) -> str:
    return (
        datetime.now(timezone.utc).replace(microsecond=0) - timedelta(days=days)
    ).isoformat().replace("+00:00", "Z")


def tail_text(path: Path, *, max_lines: int = 120) -> list[str]:
    if not path.exists():
        return []
    return path.read_text(encoding="utf-8", errors="replace").splitlines()[-max_lines:]


def write_artifact(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")


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


def launch_app(
    app_bundle: Path,
    *,
    log_path: Path,
    home_dir: Path,
    app_support_root: Path,
    config_path: Path,
) -> subprocess.Popen[str]:
    executable = app_bundle / "Contents" / "MacOS" / "GhoDex"
    if not executable.exists():
        raise RuntimeError(f"Missing app executable: {executable}")

    env = os.environ.copy()
    env["GHODEX_BROWSER_APP_SUPPORT_ROOT"] = str(app_support_root)
    env["GHOSTTY_CONFIG_PATH"] = str(config_path)
    env["HOME"] = str(home_dir)
    env["TMPDIR"] = str(home_dir / "tmp")

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


class HarnessClient:
    def __init__(self, socket_path: str, *, timeout: float, artifact: dict[str, Any]):
        self.socket_path = socket_path
        self.timeout = timeout
        self.artifact = artifact
        self.artifact.setdefault("requests", {})
        self.artifact.setdefault("request_order", [])

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
        response = send_single_request(self.socket_path, body, timeout=self.timeout)
        self.artifact["requests"][label] = {
            "request": body,
            "response": response,
        }
        self.artifact["last_successful_request_label"] = label
        self.artifact["last_successful_request_command"] = command
        if response.get("status") != "ok":
            raise RuntimeError(
                f"{command} failed: {json.dumps(response, ensure_ascii=False, sort_keys=True)}"
            )
        return response


def load_bundle_id(app_bundle: Path) -> str:
    info_plist = app_bundle / "Contents" / "Info.plist"
    with info_plist.open("rb") as handle:
        info = plistlib.load(handle)
    bundle_id = info.get("CFBundleIdentifier")
    if not isinstance(bundle_id, str) or not bundle_id:
        raise RuntimeError(f"Unable to read CFBundleIdentifier from {info_plist}")
    return bundle_id


def diagnostics_paths(bundle_id: str) -> dict[str, Path]:
    app_support = Path.home() / "Library" / "Application Support" / bundle_id
    diagnostics_dir = app_support / "Diagnostics"
    control_harness_dir = app_support / "ControlHarness"
    return {
        "app_support": app_support,
        "diagnostics_dir": diagnostics_dir,
        "control_harness_dir": control_harness_dir,
        "crash_summary_file": diagnostics_dir / "runtime-last-crash-summary.json",
        "exports_dir": diagnostics_dir / "Exports",
    }


def seed_crash_summary(crash_summary_file: Path, *, bundle_id: str) -> None:
    crash_summary_file.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "schema_version": 1,
        "processed_at": iso8601_now(),
        "marker": {
            "schema_version": 1,
            "crash_kind": "signal",
            "pid": os.getpid(),
            "bundle_id": bundle_id,
            "executable_name": "GhoDex",
            "session_id": "live-acceptance-session",
            "session_started_at": iso8601_past(1),
            "reason": "SIGABRT",
            "signal_name": "SIGABRT",
            "signal_number": 6,
            "exception_name": None,
            "exception_reason": None,
            "marker_written_at": iso8601_now(),
        },
        "matched_report": None,
        "last_breadcrumb": {
            "timestamp": iso8601_now(),
            "component": "live.acceptance",
            "event": "seeded_runtime_probe",
        },
    }
    crash_summary_file.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")


def seed_stale_export(exports_dir: Path) -> Path:
    exports_dir.mkdir(parents=True, exist_ok=True)
    stale_export = exports_dir / "stale-diagnostics-bundle.json"
    stale_export.write_text("{\"stale\":true}\n", encoding="utf-8")
    stale_epoch = (datetime.now(timezone.utc) - timedelta(days=20)).timestamp()
    os.utime(stale_export, (stale_epoch, stale_epoch))
    return stale_export


def run_acceptance(args: argparse.Namespace) -> dict[str, Any]:
    app_bundle = Path(args.app).resolve() if args.app else resolve_default_app()
    output_path = Path(args.output).expanduser().resolve()
    bundle_id = load_bundle_id(app_bundle)

    session_root = Path(f"/tmp/ghx-control-harness-diagnostics-{uuid.uuid4().hex[:8]}")
    home_dir = session_root / "home"
    app_support_root = session_root / "app-support"
    config_path = home_dir / ".config" / "ghostty" / "config"
    log_path = session_root / "app.log"
    paths = diagnostics_paths(bundle_id)

    artifact: dict[str, Any] = {
        "app": str(app_bundle),
        "bundle_id": bundle_id,
        "session_root": str(session_root),
        "log_path": str(log_path),
        "diagnostics_root": str(paths["diagnostics_dir"]),
        "verified_commands": [
            "diagnostics.status",
            "diagnostics.logs.query",
            "diagnostics.crash.latest",
            "diagnostics.mode.get",
            "diagnostics.mode.set",
            "diagnostics.retention.get",
            "diagnostics.retention.apply",
            "diagnostics.cleanup.run",
            "diagnostics.export.bundle",
        ],
    }

    proc: subprocess.Popen[str] | None = None
    current_pid: int | None = None
    socket_path: str | None = None
    client: HarnessClient | None = None
    skip_cleanup = False
    crash_summary_backup: bytes | None = None
    crash_summary_existed = paths["crash_summary_file"].exists()

    try:
        if crash_summary_existed:
            crash_summary_backup = paths["crash_summary_file"].read_bytes()

        proc = launch_app(
            app_bundle,
            log_path=log_path,
            home_dir=home_dir,
            app_support_root=app_support_root,
            config_path=config_path,
        )
        current_pid = proc.pid
        socket_path = wait_for_harness_socket(current_pid, timeout_ms=args.startup_timeout_ms)
        client = HarnessClient(socket_path, timeout=args.request_timeout, artifact=artifact)

        client.request("system.handshake")
        target = wait_until(
            "resolved live target",
            lambda: (
                response
                if int(response.get("result", {}).get("instance", {}).get("process_id") or -1) == current_pid
                else None
            )
            if (response := client.request("system.target.resolve", _label="system.target.resolve.live"))
            else None,
            timeout_ms=args.startup_timeout_ms,
        )
        initial_snapshot = wait_until(
            "initial state snapshot",
            lambda: (
                response
                if response.get("result", {}).get("tabs")
                else None
            )
            if (response := client.request("state.snapshot", _label="state.snapshot.live"))
            else None,
            timeout_ms=args.startup_timeout_ms,
        )

        seed_crash_summary(paths["crash_summary_file"], bundle_id=bundle_id)
        stale_export = seed_stale_export(paths["exports_dir"])

        diagnostics_status = wait_until(
            "diagnostics status with seeded files",
            lambda: (
                response
                if response.get("result", {}).get("latest_crash_summary_present") is True
                and int(response.get("result", {}).get("total_storage_bytes", 0)) > 0
                else None
            )
            if (response := client.request("diagnostics.status"))
            else None,
            timeout_ms=args.settle_ms,
        )

        diagnostics_mode_initial = client.request("diagnostics.mode.get")
        diagnostics_mode_configured = client.request(
            "diagnostics.mode.set",
            payload={"mode": "operational", "scope": "configured"},
        )
        settings_after_mode_configured = client.request(
            "settings.values.get",
            _label="settings.values.get.after-diagnostics-mode-configured",
        )
        diagnostics_mode_override = client.request(
            "diagnostics.mode.set",
            payload={"mode": "deep", "scope": "override", "ttl_seconds": "120"},
        )
        diagnostics_mode_cleared = client.request(
            "diagnostics.mode.set",
            payload={"scope": "override", "clear_override": "true"},
        )

        diagnostics_retention_initial = client.request("diagnostics.retention.get")
        diagnostics_retention_applied = client.request(
            "diagnostics.retention.apply",
            payload={"retention_days": "3"},
        )
        settings_after_retention = client.request(
            "settings.values.get",
            _label="settings.values.get.after-diagnostics-retention",
        )

        diagnostics_runtime_query = wait_until(
            "audit diagnostics logs query for configured mode change",
            lambda: (
                response
                if response.get("result", {}).get("records")
                else None
            )
            if (
                response := client.request(
                    "diagnostics.logs.query",
                    _label="diagnostics.logs.query.audit.mode-set",
                    payload={"source": "audit", "event": "diagnostics.mode.set"},
                    max_lines=20,
                )
            )
            else None,
            timeout_ms=args.settle_ms,
        )
        diagnostics_audit_query = wait_until(
            "audit diagnostics logs query",
            lambda: (
                response
                if response.get("result", {}).get("records")
                else None
            )
            if (
                response := client.request(
                    "diagnostics.logs.query",
                    _label="diagnostics.logs.query.audit",
                    payload={"source": "audit", "event": "diagnostics.retention.apply"},
                    max_lines=20,
                )
            )
            else None,
            timeout_ms=args.settle_ms,
        )

        diagnostics_crash_latest = client.request("diagnostics.crash.latest")
        diagnostics_export = client.request(
            "diagnostics.export.bundle",
            payload={"source": "audit"},
            max_lines=20,
        )
        exported_path = Path(diagnostics_export["result"]["path"])
        exported_payload = json.loads(exported_path.read_text(encoding="utf-8"))

        diagnostics_cleanup = client.request("diagnostics.cleanup.run")

        artifact["summary"] = {
            "resolved_process_id": target["result"]["instance"]["process_id"],
            "resolved_socket_path": target["result"]["instance"]["socket_path"],
            "initial_tab_count": len(initial_snapshot["result"]["tabs"]),
            "status_total_storage_bytes": diagnostics_status["result"]["total_storage_bytes"],
            "status_total_budget_bytes": diagnostics_status["result"]["total_budget_bytes"],
            "status_sources": diagnostics_status["result"]["sources"],
            "mode_initial": diagnostics_mode_initial["result"],
            "mode_after_configured": diagnostics_mode_configured["result"],
            "mode_after_override": diagnostics_mode_override["result"],
            "mode_after_clear_override": diagnostics_mode_cleared["result"],
            "configured_mode_setting": settings_after_mode_configured["result"]["values"]["diagnostics.mode"],
            "retention_initial_days": diagnostics_retention_initial["result"]["settings"]["retention_days"],
            "retention_applied_days": diagnostics_retention_applied["result"]["settings"]["retention_days"],
            "configured_retention_setting": settings_after_retention["result"]["values"]["diagnostics.retention_days"],
            "mode_set_audit_query_count": len(diagnostics_runtime_query["result"]["records"]),
            "audit_query_count": len(diagnostics_audit_query["result"]["records"]),
            "latest_crash_reason": diagnostics_crash_latest["result"]["summary"]["marker"]["reason"],
            "export_path": str(exported_path),
            "export_byte_count": diagnostics_export["result"]["byte_count"],
            "export_recent_error_count": len(exported_payload.get("recent_errors", [])),
            "cleanup_deleted_paths": diagnostics_cleanup["result"]["deleted_paths"],
            "cleanup_bytes_freed": diagnostics_cleanup["result"]["bytes_freed"],
            "stale_export_deleted": not stale_export.exists(),
        }

        if settings_after_mode_configured["result"]["values"]["diagnostics.mode"] != "operational":
            raise RuntimeError("Configured diagnostics.mode did not persist as operational")
        if diagnostics_mode_override["result"]["effective_mode"] != "deep":
            raise RuntimeError("diagnostics.mode.set override did not raise effective mode to deep")
        if diagnostics_mode_cleared["result"]["effective_mode"] != "operational":
            raise RuntimeError("Clearing diagnostics override did not fall back to configured mode")
        if settings_after_retention["result"]["values"]["diagnostics.retention_days"] != "3":
            raise RuntimeError("Configured diagnostics.retention_days did not persist as 3")
        if diagnostics_crash_latest["result"]["summary"]["marker"]["reason"] != "SIGABRT":
            raise RuntimeError("diagnostics.crash.latest did not return the seeded crash summary")
        if exported_payload.get("latest_crash", {}).get("marker", {}).get("reason") != "SIGABRT":
            raise RuntimeError("diagnostics.export.bundle did not include the latest crash summary")
        if stale_export.exists():
            raise RuntimeError("diagnostics.cleanup.run left the seeded stale export on disk")

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
            "proc_poll": proc.poll() if proc is not None else None,
            "current_socket": socket_path,
            "socket_exists": Path(socket_path).exists() if socket_path else False,
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
            if not skip_cleanup and proc is not None:
                terminate_process(proc)
        except Exception as exc:  # noqa: BLE001
            artifact["cleanup_error"] = str(exc)
            write_artifact(output_path, artifact)
        finally:
            if crash_summary_existed and crash_summary_backup is not None:
                paths["crash_summary_file"].parent.mkdir(parents=True, exist_ok=True)
                paths["crash_summary_file"].write_bytes(crash_summary_backup)
            elif paths["crash_summary_file"].exists():
                paths["crash_summary_file"].unlink()
            if not skip_cleanup:
                shutil.rmtree(session_root, ignore_errors=True)


def main() -> None:
    args = parse_args()
    artifact = run_acceptance(args)
    print(json.dumps(artifact, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
