#!/usr/bin/env python3

"""
Browser teardown stability acceptance harness.

This harness launches an isolated CEF-enabled GhoDex app, repeatedly creates
Browser contexts and pages through `browser.context.v2`, then closes those
pages and contexts to exercise the Browser SwiftUI teardown path that
previously crashed with a main-thread exclusivity abort.

Safety notes:
- the harness always launches the target app with an isolated `HOME`
- it relocates Browser runtime state through `GHODEX_BROWSER_APP_SUPPORT_ROOT`
- it never touches `/Applications/GhoDex.app` and never kills unrelated apps
"""

from __future__ import annotations

import argparse
import http.server
import json
import os
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
DEFAULT_OUTPUT = "/tmp/ghx-browser-teardown-stability-acceptance.json"


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
        description="Prove Browser page/context teardown stays stable under repeated close operations."
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
        "--iterations",
        type=int,
        default=10,
        help="How many create/page-close/context-close cycles to run.",
    )
    parser.add_argument(
        "--page-timeout-ms",
        type=int,
        default=90000,
        help="Timeout for socket and command readiness.",
    )
    parser.add_argument(
        "--output",
        default=DEFAULT_OUTPUT,
        help="Where to write the JSON artifact.",
    )
    parser.add_argument(
        "--settle-ms",
        type=int,
        default=1000,
        help="How long to let Browser teardown settle between close/reopen cycles.",
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
        raise RuntimeError(f"missing resultJSON in response: {json.dumps(response, sort_keys=True)}")
    return json.loads(raw)


def wait_for_socket_ready(socket_path: str, timeout_ms: int) -> dict:
    deadline = time.monotonic() + (timeout_ms / 1000.0)
    last_error: str | None = None
    while time.monotonic() < deadline:
        if os.path.exists(socket_path):
            try:
                return send_request(socket_path, "listContexts", timeout=2.0)
            except Exception as exc:  # noqa: BLE001
                last_error = str(exc)
        time.sleep(0.25)
    raise RuntimeError(f"Timed out waiting for Browser IPC socket readiness at {socket_path}: {last_error or 'no socket'}")


def wait_for_context_absent(socket_path: str, context_id: str, timeout_ms: int) -> list[dict]:
    deadline = time.monotonic() + (timeout_ms / 1000.0)
    last_contexts: list[dict] = []
    while time.monotonic() < deadline:
        list_result = extract_result_json(send_request(socket_path, "listContexts", timeout=5.0)["response"])
        assert isinstance(list_result, list)
        last_contexts = list_result
        if all(context.get("id") != context_id for context in list_result):
            return list_result
        time.sleep(0.1)
    raise RuntimeError(f"Timed out waiting for Browser context {context_id} to disappear. Last contexts: {json.dumps(last_contexts, sort_keys=True)}")


def wait_for_new_context(
    socket_path: str,
    previous_ids: set[str],
    timeout_ms: int,
) -> dict:
    deadline = time.monotonic() + (timeout_ms / 1000.0)
    last_contexts: list[dict] = []
    while time.monotonic() < deadline:
        list_result = extract_result_json(send_request(socket_path, "listContexts", timeout=5.0)["response"])
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


def wait_for_page_bridge_ready(
    socket_path: str,
    *,
    browser_context_id: str,
    page_id: str,
    timeout_ms: int,
) -> dict:
    deadline = time.monotonic() + (timeout_ms / 1000.0)
    last_response: dict | None = None
    while time.monotonic() < deadline:
        remaining = max(1.0, deadline - time.monotonic())
        try:
            probe = send_request(
                socket_path,
                "listFrames",
                browser_context_id=browser_context_id,
                page_id=page_id,
                timeout=min(remaining, 20.0),
            )
        except TimeoutError:
            last_response = {
                "timed_out": True,
                "browserContextID": browser_context_id,
                "pageID": page_id,
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
        f"context={browser_context_id} page={page_id} last={json.dumps(last_response or {}, sort_keys=True)}"
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


@contextmanager
def local_browser_server() -> dict[str, str]:
    webroot = Path(f"/tmp/ghx-browser-teardown-web-{uuid.uuid4().hex[:8]}")
    if webroot.exists():
        shutil.rmtree(webroot, ignore_errors=True)
    webroot.mkdir(parents=True, exist_ok=True)

    html = """<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <title>browser-teardown</title>
  </head>
  <body>
    <h1 id="teardown-root">browser-teardown</h1>
    <script>
      window.__ghodexTeardownReady = true;
    </script>
  </body>
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

    session_root = Path(f"/tmp/ghx-browser-teardown-{uuid.uuid4().hex[:8]}")
    if session_root.exists():
        shutil.rmtree(session_root, ignore_errors=True)
    session_root.mkdir(parents=True, exist_ok=True)
    app_support_root = session_root / "app-support"
    home_dir = session_root / "home"
    log_path = session_root / "app.log"
    socket_path = app_support_root / "browser-control.sock"

    proc: subprocess.Popen[str] | None = None
    success = False
    result: dict[str, object] = {
        "app": str(app_bundle),
        "runtime_root": runtime_root,
        "iterations_requested": args.iterations,
        "session_root": str(session_root),
        "log_path": str(log_path),
        "socket_path": str(socket_path),
        "cycles": [],
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
            )

            result["socket_ready_probe"] = wait_for_socket_ready(str(socket_path), args.page_timeout_ms)
            context_url = server_info["main_url"]
            command_timeout = max(45.0, args.page_timeout_ms / 1000.0)

            for iteration in range(args.iterations):
                cycle: dict[str, object] = {"iteration": iteration + 1}
                contexts_before = extract_result_json(send_request(str(socket_path), "listContexts", timeout=10.0)["response"])
                assert isinstance(contexts_before, list)
                previous_context_ids = {str(context["id"]) for context in contexts_before}

                new_context = send_request(
                    str(socket_path),
                    "newContext",
                    payload={"url": context_url},
                    timeout=command_timeout,
                )
                if new_context["response"].get("ok") is True:
                    context_summary = extract_result_json(new_context["response"])
                    assert isinstance(context_summary, dict)
                else:
                    error = new_context["response"].get("error") or {}
                    if error.get("code") != "bridgeUnavailable":
                        raise RuntimeError(
                            f"newContext failed unexpectedly: {json.dumps(new_context['response'], sort_keys=True)}"
                        )
                    context_summary = wait_for_new_context(
                        str(socket_path),
                        previous_context_ids,
                        args.page_timeout_ms,
                    )
                    cycle["new_context_recovered_after_bridge_timeout"] = True
                context_id = str(context_summary["id"])
                active_page_id = str(context_summary["activePageID"])
                cycle["new_context"] = new_context
                cycle["resolved_context_summary"] = context_summary
                cycle["initial_page_bridge_ready"] = wait_for_page_bridge_ready(
                    str(socket_path),
                    browser_context_id=context_id,
                    page_id=active_page_id,
                    timeout_ms=args.page_timeout_ms,
                )

                new_page = send_request(
                    str(socket_path),
                    "newPageInContext",
                    browser_context_id=context_id,
                    payload={"url": context_url},
                    timeout=command_timeout,
                )
                page_summary = extract_result_json(new_page["response"])
                assert isinstance(page_summary, dict)
                page_id = str(page_summary["id"])
                cycle["new_page"] = new_page
                cycle["new_page_bridge_ready"] = wait_for_page_bridge_ready(
                    str(socket_path),
                    browser_context_id=context_id,
                    page_id=page_id,
                    timeout_ms=args.page_timeout_ms,
                )

                cycle["close_page"] = send_request(
                    str(socket_path),
                    "closePage",
                    browser_context_id=context_id,
                    page_id=page_id,
                    timeout=command_timeout,
                )

                cycle["close_context"] = send_request(
                    str(socket_path),
                    "closeContext",
                    browser_context_id=context_id,
                    timeout=command_timeout,
                )

                cycle["contexts_after_close"] = wait_for_context_absent(
                    str(socket_path),
                    context_id,
                    args.page_timeout_ms,
                )
                if args.settle_ms > 0:
                    time.sleep(args.settle_ms / 1000.0)
                wait_for_process_alive(proc, 1000)
                result["cycles"].append(cycle)

            result["post_check"] = send_request(str(socket_path), "listContexts", timeout=10.0)
            wait_for_process_alive(proc, 1000)
            result["acceptance"] = {
                "all_cycles_completed": len(result["cycles"]) == args.iterations,
                "process_alive_after_cycles": proc.poll() is None,
                "post_check_ok": result["post_check"]["response"].get("ok") is True,
                "no_unexpected_exit": proc.poll() is None,
            }
            result["status"] = "passed"
            success = True
            output_path.write_text(json.dumps(result, indent=2), encoding="utf-8")
            print(json.dumps(result, indent=2))
            return 0
    except Exception as exc:  # noqa: BLE001
        result["status"] = "failed"
        result["error"] = str(exc)
        result["log_tail"] = log_path.read_text(errors="replace").splitlines()[-20:] if log_path.exists() else []
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
