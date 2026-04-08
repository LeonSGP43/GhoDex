#!/usr/bin/env python3

"""
Browser last-window close acceptance harness.

This harness proves that closing the last Browser window/context does not
terminate the whole GhoDex app, even when `quit-after-last-window-closed = true`
is enabled in the isolated test config.
"""

from __future__ import annotations

import argparse
import http.server
import json
import os
import plistlib
import re
import shutil
import socket
import socketserver
import subprocess
import threading
import time
import uuid
from contextlib import contextmanager
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = "/tmp/ghx-browser-last-window-close-acceptance.json"
HARNESS_SOCKET_RE = re.compile(r"(?P<path>/Users/.*/ControlHarness/harness\.sock)$")


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
        description=(
            "Prove that closing the last Browser window/context does not quit "
            "the whole app."
        )
    )
    parser.add_argument(
        "--app",
        default=None,
        help="Path to the CEF-enabled GhoDex.app bundle to launch.",
    )
    parser.add_argument(
        "--runtime-root",
        default=str(REPO_ROOT / "macos" / "build" / "cef-runtime" / "current"),
        help="CEF runtime root passed through GHODEX_CEF_ROOT.",
    )
    parser.add_argument(
        "--page-timeout-ms",
        type=int,
        default=90000,
        help="Timeout budget for page readiness and lifecycle commands.",
    )
    parser.add_argument(
        "--settle-ms",
        type=int,
        default=2000,
        help="How long to wait after Browser close before probing app liveness.",
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
        raise RuntimeError("socket closed before a response line was received")
    return data.decode().strip()


def send_request(
    socket_path: str,
    command: str,
    *,
    version: str = "browser.context.v2",
    browser_context_id: str | None = None,
    page_id: str | None = None,
    payload: dict[str, str] | None = None,
    timeout: float = 30.0,
) -> dict:
    body = {
        "id": str(uuid.uuid4()),
        "version": version,
        "command": command,
        "payload": payload or {},
    }
    if browser_context_id is not None:
        body["browserContextID"] = browser_context_id
    if page_id is not None:
        body["pageID"] = page_id

    started = time.perf_counter()
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(timeout)
    client.connect(socket_path)
    client.sendall((json.dumps(body) + "\n").encode())
    line = recv_line(client)
    client.close()
    elapsed_ms = round((time.perf_counter() - started) * 1000, 2)
    return {"elapsed_ms": elapsed_ms, "request": body, "response": json.loads(line)}


def extract_result_json(response: dict) -> dict | list:
    if response.get("ok") is not True:
        raise RuntimeError(f"request failed: {json.dumps(response, sort_keys=True)}")
    raw = response.get("resultJSON")
    if not isinstance(raw, str):
        raise RuntimeError(
            f"missing resultJSON in response: {json.dumps(response, sort_keys=True)}"
        )
    return json.loads(raw)


def wait_for_socket_ready(socket_path: str, timeout_ms: int) -> dict:
    deadline = time.monotonic() + (timeout_ms / 1000.0)
    last_error: str | None = None
    while time.monotonic() < deadline:
        if os.path.exists(socket_path):
            try:
                return send_request(socket_path, "listContexts", timeout=5.0)
            except Exception as exc:  # noqa: BLE001
                last_error = str(exc)
        time.sleep(0.25)
    raise RuntimeError(
        f"Timed out waiting for Browser IPC socket readiness at {socket_path}: "
        f"{last_error or 'no socket'}"
    )


def wait_for_new_context(
    socket_path: str,
    previous_ids: set[str],
    timeout_ms: int,
) -> dict:
    deadline = time.monotonic() + (timeout_ms / 1000.0)
    last_contexts: list[dict] = []
    while time.monotonic() < deadline:
        list_result = extract_result_json(
            send_request(socket_path, "listContexts", timeout=10.0)["response"]
        )
        assert isinstance(list_result, list)
        last_contexts = list_result
        for context in list_result:
            context_id = str(context.get("id", ""))
            if context_id and context_id not in previous_ids:
                return context
        time.sleep(0.1)
    raise RuntimeError(
        "Timed out waiting for a new Browser context to appear. "
        f"Last contexts: {json.dumps(last_contexts, sort_keys=True)}"
    )


def wait_for_context_absent(socket_path: str, context_id: str, timeout_ms: int) -> list[dict]:
    deadline = time.monotonic() + (timeout_ms / 1000.0)
    last_contexts: list[dict] = []
    while time.monotonic() < deadline:
        list_result = extract_result_json(
            send_request(socket_path, "listContexts", timeout=10.0)["response"]
        )
        assert isinstance(list_result, list)
        last_contexts = list_result
        if all(context.get("id") != context_id for context in list_result):
            return list_result
        time.sleep(0.1)
    raise RuntimeError(
        f"Timed out waiting for Browser context {context_id} to disappear. "
        f"Last contexts: {json.dumps(last_contexts, sort_keys=True)}"
    )


def wait_for_page_bridge_ready(
    socket_path: str,
    *,
    browser_context_id: str,
    page_id: str,
    selector: str,
    timeout_ms: int,
) -> dict:
    deadline = time.monotonic() + (timeout_ms / 1000.0)
    last_response: dict | None = None
    while time.monotonic() < deadline:
        remaining = max(1.0, deadline - time.monotonic())
        try:
            probe = send_request(
                socket_path,
                "waitForSelector",
                browser_context_id=browser_context_id,
                page_id=page_id,
                payload={"selector": selector},
                timeout=min(remaining, 20.0),
            )
        except TimeoutError:
            last_response = {
                "timed_out": True,
                "browserContextID": browser_context_id,
                "pageID": page_id,
                "selector": selector,
            }
            time.sleep(0.25)
            continue

        last_response = probe
        response = probe["response"]
        if response.get("ok") is True:
            return probe

        error = response.get("error") or {}
        if error.get("code") not in {"bridgeUnavailable", "requestTimedOut"}:
            raise RuntimeError(
                "Unexpected page bridge readiness failure: "
                f"{json.dumps(response, sort_keys=True)}"
            )
        time.sleep(0.25)

    raise RuntimeError(
        "Timed out waiting for page bridge readiness. "
        f"context={browser_context_id} page={page_id} "
        f"last={json.dumps(last_response or {}, sort_keys=True)}"
    )


def discover_harness_socket(pid: int, timeout_ms: int) -> str:
    deadline = time.monotonic() + (timeout_ms / 1000.0)
    last_lsof = ""
    while time.monotonic() < deadline:
        completed = subprocess.run(
            ["lsof", "-Pan", "-p", str(pid)],
            capture_output=True,
            text=True,
            timeout=10.0,
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


def terminal_snapshot_summary(snapshot: dict) -> dict[str, object]:
    result = snapshot.get("result") or {}
    tabs = result.get("tabs") or []
    terminals = [terminal for tab in tabs for terminal in tab.get("terminals") or []]
    return {
        "tab_count": len(tabs),
        "terminal_count": len(terminals),
        "tabs": tabs,
        "terminals": terminals,
    }


def close_only_terminal_window_via_harness(app_bundle: Path, harness_socket: str) -> dict[str, object]:
    before = run_control_command(app_bundle, harness_socket, "snapshot")
    before_summary = terminal_snapshot_summary(before)
    if before_summary["terminal_count"] != 1:
        raise RuntimeError(
            "Expected exactly one terminal before closing it, got "
            f"{before_summary['terminal_count']}"
        )

    terminals = before_summary["terminals"]
    terminal_id = str(terminals[0]["terminal_id"])
    close_result = run_control_command(
        app_bundle,
        harness_socket,
        "close-terminal",
        f"--terminal-id={terminal_id}",
    )
    deadline = time.monotonic() + 15.0
    after = None
    while time.monotonic() < deadline:
        after = run_control_command(app_bundle, harness_socket, "snapshot")
        after_summary = terminal_snapshot_summary(after)
        if after_summary["terminal_count"] == 0:
            return {
                "terminal_id": terminal_id,
                "before": before_summary,
                "close_result": close_result,
                "after": after_summary,
            }
        time.sleep(0.25)

    raise RuntimeError(
        "Timed out waiting for the initial terminal window to close. "
        f"Last snapshot: {json.dumps(terminal_snapshot_summary(after or {}), sort_keys=True)}"
    )


def wait_for_process_alive(proc: subprocess.Popen[str], timeout_ms: int) -> None:
    deadline = time.monotonic() + (timeout_ms / 1000.0)
    while time.monotonic() < deadline:
        if proc.poll() is None:
            return
        time.sleep(0.05)
    raise RuntimeError(f"GhoDex exited unexpectedly with status {proc.returncode}")


def wait_for_socket_gone(socket_path: str, timeout_ms: int) -> None:
    deadline = time.monotonic() + (timeout_ms / 1000.0)
    while time.monotonic() < deadline:
        if not os.path.exists(socket_path):
            return
        time.sleep(0.25)
    raise RuntimeError(f"Timed out waiting for Browser IPC socket removal at {socket_path}")


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


def write_test_config(config_path: Path) -> None:
    config_path.parent.mkdir(parents=True, exist_ok=True)
    config_path.write_text(
        "\n".join(
            [
                "initial-window = true",
                "quit-after-last-window-closed = true",
                "macos-applescript = true",
                "",
            ]
        ),
        encoding="utf-8",
    )


def app_bundle_identifier(app_bundle: Path) -> str:
    info_plist = app_bundle / "Contents" / "Info.plist"
    if not info_plist.exists():
        raise RuntimeError(f"App Info.plist does not exist: {info_plist}")

    with info_plist.open("rb") as handle:
        plist = plistlib.load(handle)

    bundle_id = plist.get("CFBundleIdentifier")
    if not isinstance(bundle_id, str) or not bundle_id:
        raise RuntimeError(f"App bundle identifier is missing from {info_plist}")

    return bundle_id


def run_osascript(app_bundle: Path, script_lines: list[str], timeout: float = 15.0) -> str:
    bundle_id = app_bundle_identifier(app_bundle)
    command = ["osascript"]
    command.extend(["-e", f'tell application id "{bundle_id}"'])
    for line in script_lines:
        command.extend(["-e", line])
    command.extend(["-e", "end tell"])
    completed = subprocess.run(
        command,
        check=True,
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    return completed.stdout.strip()


def wait_for_terminal_window_count(app_bundle: Path, expected_count: int, timeout_ms: int) -> int:
    deadline = time.monotonic() + (timeout_ms / 1000.0)
    last_value = -1
    while time.monotonic() < deadline:
        try:
            stdout = run_osascript(app_bundle, ["count windows"])
            last_value = int(stdout or "0")
            if last_value == expected_count:
                return last_value
        except Exception:  # noqa: BLE001
            pass
        time.sleep(0.25)

    raise RuntimeError(
        f"Timed out waiting for terminal window count {expected_count}. "
        f"Last observed count: {last_value}"
    )


def wait_for_browser_tab_count(app_bundle: Path, expected_count: int, timeout_ms: int) -> int:
    deadline = time.monotonic() + (timeout_ms / 1000.0)
    last_value = -1
    while time.monotonic() < deadline:
        try:
            stdout = run_osascript(app_bundle, ["count browser tabs"])
            last_value = int(stdout or "0")
            if last_value == expected_count:
                return last_value
        except Exception:  # noqa: BLE001
            pass
        time.sleep(0.25)

    raise RuntimeError(
        f"Timed out waiting for browser tab count {expected_count}. "
        f"Last observed count: {last_value}"
    )


def close_only_terminal_window(app_bundle: Path, timeout_ms: int) -> dict[str, object]:
    before = wait_for_terminal_window_count(app_bundle, 1, timeout_ms)
    run_osascript(app_bundle, ["close window 1"])
    after = wait_for_terminal_window_count(app_bundle, 0, timeout_ms)
    return {
        "terminal_windows_before_close": before,
        "terminal_windows_after_close": after,
    }


def launch_app(
    app_bundle: Path,
    log_path: Path,
    *,
    runtime_root: str,
    app_support_root: Path,
    home_dir: Path,
    config_path: Path,
) -> subprocess.Popen[str]:
    executable = app_bundle / "Contents" / "MacOS" / "GhoDex"
    if not executable.exists():
        raise RuntimeError(f"App executable does not exist: {executable}")

    env = os.environ.copy()
    env["GHODEX_CEF_ROOT"] = runtime_root
    env["GHODEX_BROWSER_APP_SUPPORT_ROOT"] = str(app_support_root)
    env["GHOSTTY_CONFIG_PATH"] = str(config_path)
    env["HOME"] = str(home_dir)
    env["TMPDIR"] = str(home_dir / "tmp")
    env.pop("GHODEX_CEF_PROFILE_PATH", None)

    home_dir.mkdir(parents=True, exist_ok=True)
    (home_dir / "tmp").mkdir(parents=True, exist_ok=True)
    app_support_root.mkdir(parents=True, exist_ok=True)
    write_test_config(config_path)
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


@contextmanager
def local_browser_server() -> dict[str, str]:
    webroot = Path(f"/tmp/ghx-browser-last-window-web-{uuid.uuid4().hex[:8]}")
    if webroot.exists():
        shutil.rmtree(webroot, ignore_errors=True)
    webroot.mkdir(parents=True, exist_ok=True)

    html = """<!doctype html>
<html>
  <head><meta charset="utf-8"><title>browser-last-window-close</title></head>
  <body><h1 id="browser-last-window-close">browser-last-window-close</h1></body>
</html>
"""
    (webroot / "index.html").write_text(html, encoding="utf-8")

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
        port = server.server_address[1]
        yield {
            "main_url": f"http://127.0.0.1:{port}/index.html",
            "webroot": str(webroot),
        }
    finally:
        server.shutdown()
        server.server_close()
        shutil.rmtree(webroot, ignore_errors=True)


def main() -> int:
    args = parse_args()
    app_bundle = Path(args.app).expanduser() if args.app else resolve_default_app()
    runtime_root = str(Path(args.runtime_root).expanduser())
    output_path = Path(args.output)

    session_root = Path(f"/tmp/ghx-browser-last-window-close-{uuid.uuid4().hex[:8]}")
    if session_root.exists():
        shutil.rmtree(session_root, ignore_errors=True)
    session_root.mkdir(parents=True, exist_ok=True)
    app_support_root = session_root / "app-support"
    home_dir = session_root / "home"
    config_path = session_root / "ghostty.config"
    log_path = session_root / "app.log"
    socket_path = app_support_root / "browser-control.sock"

    proc: subprocess.Popen[str] | None = None
    success = False
    result: dict[str, object] = {
        "app": str(app_bundle),
        "runtime_root": runtime_root,
        "session_root": str(session_root),
        "config_path": str(config_path),
        "log_path": str(log_path),
        "socket_path": str(socket_path),
        "status": "running",
    }

    try:
        with local_browser_server() as server_info:
            result["server"] = server_info
            proc = launch_app(
                app_bundle,
                log_path,
                runtime_root=runtime_root,
                app_support_root=app_support_root,
                home_dir=home_dir,
                config_path=config_path,
            )

            result["socket_ready_probe"] = wait_for_socket_ready(
                str(socket_path), args.page_timeout_ms
            )
            result["harness_socket"] = discover_harness_socket(proc.pid, args.page_timeout_ms)
            result["initial_terminal_snapshot"] = terminal_snapshot_summary(
                run_control_command(app_bundle, result["harness_socket"], "snapshot")
            )
            contexts_before = extract_result_json(
                send_request(str(socket_path), "listContexts", timeout=10.0)["response"]
            )
            assert isinstance(contexts_before, list)
            result["initial_contexts"] = contexts_before
            previous_context_ids = {str(context["id"]) for context in contexts_before}
            command_timeout = max(45.0, args.page_timeout_ms / 1000.0)

            create_context = send_request(
                str(socket_path),
                "newContext",
                payload={"url": server_info["main_url"]},
                timeout=command_timeout,
            )
            if create_context["response"].get("ok") is True:
                context_summary = extract_result_json(create_context["response"])
                assert isinstance(context_summary, dict)
            else:
                error = create_context["response"].get("error") or {}
                if error.get("code") != "bridgeUnavailable":
                    raise RuntimeError(
                        "newContext failed unexpectedly: "
                        f"{json.dumps(create_context['response'], sort_keys=True)}"
                    )
                context_summary = wait_for_new_context(
                    str(socket_path), previous_context_ids, args.page_timeout_ms
                )
                result["new_context_recovered_after_bridge_timeout"] = True

            context_id = str(context_summary["id"])
            page_id = str(context_summary["activePageID"])
            result["new_context"] = create_context
            result["resolved_context_summary"] = context_summary
            result["initial_page_bridge_ready"] = wait_for_page_bridge_ready(
                str(socket_path),
                browser_context_id=context_id,
                page_id=page_id,
                selector="#browser-last-window-close",
                timeout_ms=args.page_timeout_ms,
            )
            result["contexts_after_create"] = extract_result_json(
                send_request(str(socket_path), "listContexts", timeout=10.0)["response"]
            )
            result["activate_context"] = send_request(
                str(socket_path),
                "activateContext",
                browser_context_id=context_id,
                timeout=command_timeout,
            )
            result["close_terminal_window"] = close_only_terminal_window_via_harness(
                app_bundle, result["harness_socket"]
            )
            wait_for_process_alive(proc, 1000)

            result["close_context"] = send_request(
                str(socket_path),
                "closeContext",
                browser_context_id=context_id,
                timeout=command_timeout,
            )
            result["contexts_after_close"] = wait_for_context_absent(
                str(socket_path), context_id, args.page_timeout_ms
            )

            if args.settle_ms > 0:
                time.sleep(args.settle_ms / 1000.0)

            wait_for_process_alive(proc, 1000)
            result["post_close_process_alive"] = True
            result["post_close_probe"] = send_request(
                str(socket_path),
                "listContexts",
                timeout=10.0,
            )
            post_close_contexts = extract_result_json(result["post_close_probe"]["response"])
            assert isinstance(post_close_contexts, list)
            result["post_close_contexts"] = post_close_contexts

            result["acceptance"] = {
                "started_with_single_terminal_window": (
                    result["initial_terminal_snapshot"]["terminal_count"] == 1
                ),
                "created_single_browser_tab": (
                    len(result["contexts_after_create"]) == 1
                ),
                "terminal_window_closed_before_browser_close": (
                    result["close_terminal_window"]["after"]["terminal_count"] == 0
                ),
                "browser_context_closed": all(
                    context.get("id") != context_id for context in result["contexts_after_close"]
                ),
                "process_alive_after_browser_close": proc.poll() is None,
                "browser_ipc_alive_after_browser_close": (
                    result["post_close_probe"]["response"].get("ok") is True
                ),
            }
            result["status"] = "passed"
            success = True
            output_path.write_text(json.dumps(result, indent=2), encoding="utf-8")
            print(json.dumps(result, indent=2))
            return 0
    except Exception as exc:  # noqa: BLE001
        result["status"] = "failed"
        result["error"] = str(exc)
        result["log_tail"] = (
            log_path.read_text(errors="replace").splitlines()[-20:]
            if log_path.exists()
            else []
        )
        output_path.write_text(json.dumps(result, indent=2), encoding="utf-8")
        print(json.dumps(result, indent=2))
        raise
    finally:
        if proc is not None:
            terminate_process(proc)
            try:
                wait_for_socket_gone(str(socket_path), 15000)
            except RuntimeError:
                pass
        if success:
            shutil.rmtree(session_root, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
