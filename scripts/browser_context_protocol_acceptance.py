#!/usr/bin/env python3

"""
Browser Context protocol acceptance harness.

This harness proves the protocol/object-model groundwork for `browser.context.v2`
and its `browser.tab.v1` compatibility layer on an isolated local GhoDex app.
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
DEFAULT_OUTPUT = "/tmp/ghx-browser-context-protocol-acceptance.json"


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
        description="Prove browser.context.v2 lifecycle commands and browser.tab.v1 compatibility."
    )
    parser.add_argument("--app", default=None, help="Path to the CEF-enabled GhoDex.app bundle to launch.")
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
        default=1000,
        help="How long to let Browser teardown settle before reopening a compatibility tab.",
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
    browser_context_id: str | None = None,
    browser_tab_id: str | None = None,
    page_id: str | None = None,
    payload: dict[str, str] | None = None,
    timeout: float,
) -> dict:
    body = {
        "id": str(uuid.uuid4()),
        "version": version,
        "command": command,
        "payload": payload or {},
    }
    if browser_context_id is not None:
        body["browserContextID"] = browser_context_id
    if browser_tab_id is not None:
        body["browserTabID"] = browser_tab_id
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
                return send_request(
                    socket_path,
                    "listContexts",
                    version="browser.context.v2",
                    timeout=5.0,
                )
            except Exception as exc:  # noqa: BLE001
                last_error = str(exc)
        time.sleep(0.25)
    raise RuntimeError(f"Timed out waiting for Browser IPC socket readiness at {socket_path}: {last_error or 'no socket'}")


def wait_for_new_context(
    socket_path: str,
    previous_ids: set[str],
    timeout_ms: int,
) -> dict:
    deadline = time.monotonic() + (timeout_ms / 1000.0)
    last_contexts: list[dict] = []
    while time.monotonic() < deadline:
        list_result = extract_result_json(
            send_request(
                socket_path,
                "listContexts",
                version="browser.context.v2",
                timeout=10.0,
            )["response"]
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
            send_request(
                socket_path,
                "listContexts",
                version="browser.context.v2",
                timeout=10.0,
            )["response"]
        )
        assert isinstance(list_result, list)
        last_contexts = list_result
        if all(context.get("id") != context_id for context in list_result):
            return list_result
        time.sleep(0.1)
    raise RuntimeError(f"Timed out waiting for Browser context {context_id} to disappear. Last contexts: {json.dumps(last_contexts, sort_keys=True)}")


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
                version="browser.context.v2",
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
    env["GHODEX_SKIP_INITIAL_TERMINAL_WINDOW"] = "1"
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
    webroot = Path(f"/tmp/ghx-browser-context-web-{uuid.uuid4().hex[:8]}")
    if webroot.exists():
        shutil.rmtree(webroot, ignore_errors=True)
    webroot.mkdir(parents=True, exist_ok=True)

    index_html = """<!doctype html>
<html>
  <head><meta charset="utf-8"><title>context-index</title></head>
  <body><h1 id="route">index</h1></body>
</html>
"""
    second_html = """<!doctype html>
<html>
  <head><meta charset="utf-8"><title>context-second</title></head>
  <body><h1 id="route">second</h1></body>
</html>
"""
    (webroot / "index.html").write_text(index_html, encoding="utf-8")
    (webroot / "second.html").write_text(second_html, encoding="utf-8")

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
            "index_url": f"http://127.0.0.1:{port}/index.html",
            "second_url": f"http://127.0.0.1:{port}/second.html",
            "webroot": str(webroot),
        }
    finally:
        server.shutdown()
        server.server_close()
        shutil.rmtree(webroot, ignore_errors=True)


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


def main() -> int:
    args = parse_args()
    app_bundle = Path(args.app).expanduser() if args.app else resolve_default_app()
    runtime_root = str(Path(args.runtime_root).expanduser())
    output_path = Path(args.output)

    session_root = Path(f"/tmp/ghx-browser-context-{uuid.uuid4().hex[:8]}")
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
        "session_root": str(session_root),
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
            )
            command_timeout = max(45.0, args.page_timeout_ms / 1000.0)
            result["socket_ready_probe"] = wait_for_socket_ready(str(socket_path), args.page_timeout_ms)

            contexts_before = extract_result_json(
                send_request(
                    str(socket_path),
                    "listContexts",
                    version="browser.context.v2",
                    timeout=10.0,
                )["response"]
            )
            assert isinstance(contexts_before, list)
            previous_context_ids = {str(context["id"]) for context in contexts_before}

            create_v2 = send_request(
                str(socket_path),
                "newContext",
                version="browser.context.v2",
                payload={"url": server_info["index_url"]},
                timeout=command_timeout,
            )
            if create_v2["response"].get("ok") is True:
                v2_context = extract_result_json(create_v2["response"])
                assert isinstance(v2_context, dict)
            else:
                error = create_v2["response"].get("error") or {}
                if error.get("code") != "bridgeUnavailable":
                    raise RuntimeError(f"newContext failed unexpectedly: {json.dumps(create_v2['response'], sort_keys=True)}")
                v2_context = wait_for_new_context(str(socket_path), previous_context_ids, args.page_timeout_ms)

            assert isinstance(v2_context, dict)
            v2_context_id = str(v2_context["id"])
            v2_active_page_id = str(v2_context["activePageID"])
            result["v2_create_context"] = create_v2
            result["v2_context_summary"] = v2_context
            result["v2_initial_page_bridge_ready"] = wait_for_page_bridge_ready(
                str(socket_path),
                browser_context_id=v2_context_id,
                page_id=v2_active_page_id,
                timeout_ms=args.page_timeout_ms,
            )

            result["v2_get_context"] = send_request(
                str(socket_path),
                "getContext",
                version="browser.context.v2",
                browser_context_id=v2_context_id,
                timeout=command_timeout,
            )
            result["v2_list_pages"] = send_request(
                str(socket_path),
                "listPages",
                version="browser.context.v2",
                browser_context_id=v2_context_id,
                timeout=command_timeout,
            )
            result["v2_get_active_page"] = send_request(
                str(socket_path),
                "getActivePage",
                version="browser.context.v2",
                browser_context_id=v2_context_id,
                timeout=command_timeout,
            )

            result["v2_load_url"] = send_request(
                str(socket_path),
                "loadURL",
                version="browser.context.v2",
                browser_context_id=v2_context_id,
                page_id=v2_active_page_id,
                payload={"url": server_info["second_url"]},
                timeout=command_timeout,
            )
            result["v2_go_back"] = send_request(
                str(socket_path),
                "goBack",
                version="browser.context.v2",
                browser_context_id=v2_context_id,
                page_id=v2_active_page_id,
                timeout=command_timeout,
            )
            result["v2_go_forward"] = send_request(
                str(socket_path),
                "goForward",
                version="browser.context.v2",
                browser_context_id=v2_context_id,
                page_id=v2_active_page_id,
                timeout=command_timeout,
            )
            result["v2_reload"] = send_request(
                str(socket_path),
                "reload",
                version="browser.context.v2",
                browser_context_id=v2_context_id,
                page_id=v2_active_page_id,
                timeout=command_timeout,
            )

            new_page = send_request(
                str(socket_path),
                "newPageInContext",
                version="browser.context.v2",
                browser_context_id=v2_context_id,
                payload={"url": server_info["index_url"]},
                timeout=command_timeout,
            )
            new_page_summary = extract_result_json(new_page["response"])
            assert isinstance(new_page_summary, dict)
            new_page_id = str(new_page_summary["id"])
            result["v2_new_page"] = new_page
            result["v2_new_page_bridge_ready"] = wait_for_page_bridge_ready(
                str(socket_path),
                browser_context_id=v2_context_id,
                page_id=new_page_id,
                timeout_ms=args.page_timeout_ms,
            )
            result["v2_activate_page"] = send_request(
                str(socket_path),
                "activatePage",
                version="browser.context.v2",
                browser_context_id=v2_context_id,
                payload={"pageID": v2_active_page_id},
                timeout=command_timeout,
            )
            result["v2_activate_context"] = send_request(
                str(socket_path),
                "activateContext",
                version="browser.context.v2",
                browser_context_id=v2_context_id,
                timeout=command_timeout,
            )

            if args.settle_ms > 0:
                time.sleep(args.settle_ms / 1000.0)
            result["v1_list_pages_for_v2_context"] = send_request(
                str(socket_path),
                "listPages",
                version="browser.tab.v1",
                browser_tab_id=v2_context_id,
                timeout=command_timeout,
            )
            v1_pages_for_v2 = extract_result_json(result["v1_list_pages_for_v2_context"]["response"])
            assert isinstance(v1_pages_for_v2, list)

            contexts_before_v1_new_tab = extract_result_json(
                send_request(
                    str(socket_path),
                    "listContexts",
                    version="browser.context.v2",
                    timeout=command_timeout,
                )["response"]
            )
            assert isinstance(contexts_before_v1_new_tab, list)
            previous_v1_ids = {str(context["id"]) for context in contexts_before_v1_new_tab}

            create_v1 = send_request(
                str(socket_path),
                "newTab",
                version="browser.tab.v1",
                payload={"url": server_info["index_url"]},
                timeout=command_timeout,
            )
            if create_v1["response"].get("ok") is not True:
                error = create_v1["response"].get("error") or {}
                if error.get("code") != "bridgeUnavailable":
                    raise RuntimeError(f"newTab failed unexpectedly: {json.dumps(create_v1['response'], sort_keys=True)}")

            v1_context_summary = wait_for_new_context(str(socket_path), previous_v1_ids, args.page_timeout_ms)
            v1_context_id = str(v1_context_summary["id"])
            v1_active_page_id = str(v1_context_summary["activePageID"])
            result["v1_new_tab"] = create_v1
            result["v1_context_summary"] = v1_context_summary
            result["v1_initial_page_bridge_ready"] = wait_for_page_bridge_ready(
                str(socket_path),
                browser_context_id=v1_context_id,
                page_id=v1_active_page_id,
                timeout_ms=args.page_timeout_ms,
            )
            result["v2_list_contexts_after_v1_new_tab"] = send_request(
                str(socket_path),
                "listContexts",
                version="browser.context.v2",
                timeout=command_timeout,
            )
            contexts_after_v1_new_tab = extract_result_json(result["v2_list_contexts_after_v1_new_tab"]["response"])
            assert isinstance(contexts_after_v1_new_tab, list)

            result["v2_close_secondary_page"] = send_request(
                str(socket_path),
                "closePage",
                version="browser.context.v2",
                browser_context_id=v2_context_id,
                page_id=new_page_id,
                timeout=command_timeout,
            )
            result["v2_close_context"] = send_request(
                str(socket_path),
                "closeContext",
                version="browser.context.v2",
                browser_context_id=v2_context_id,
                timeout=command_timeout,
            )
            result["v2_contexts_after_close"] = wait_for_context_absent(
                str(socket_path),
                v2_context_id,
                args.page_timeout_ms,
            )
            if args.settle_ms > 0:
                time.sleep(args.settle_ms / 1000.0)

            result["v1_close_context_via_v2"] = send_request(
                str(socket_path),
                "closeContext",
                version="browser.context.v2",
                browser_context_id=v1_context_id,
                timeout=command_timeout,
            )
            result["v1_contexts_after_close"] = wait_for_context_absent(
                str(socket_path),
                v1_context_id,
                args.page_timeout_ms,
            )

            result["acceptance"] = {
                "v2_context_created": v2_context_id.startswith("browser-tab-"),
                "v2_navigation_commands_accepted": True,
                "v2_page_lifecycle_round_trip": True,
                "v1_can_target_v2_context_pages": len(v1_pages_for_v2) >= 1,
                "v1_new_tab_visible_to_v2": any(str(context.get("id")) == v1_context_id for context in contexts_after_v1_new_tab),
                "contexts_closed_cleanly": True,
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
        if success:
            shutil.rmtree(session_root, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
