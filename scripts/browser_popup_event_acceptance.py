#!/usr/bin/env python3

"""
Browser popup event acceptance harness.

This harness launches an isolated CEF-enabled GhoDex app, serves a deterministic
local popup test page, exercises both page-tab and new-window popup routing
through `browser.tab.v1`, and archives the observed `popupRequest` envelopes.

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
import tempfile
import threading
import time
import uuid
from contextlib import contextmanager
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = "/tmp/ghx-browser-popup-event-acceptance.json"


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
        description="Prove popupRequest event visibility through the Browser IPC surface."
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
        help="Timeout for socket, bridge, and popup event readiness.",
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
    version: str = "browser.tab.v1",
    browser_tab_id: str | None = None,
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
                return send_request(socket_path, "listTabs", timeout=2.0)
            except Exception as exc:  # noqa: BLE001
                last_error = str(exc)
        time.sleep(0.25)
    raise RuntimeError(f"Timed out waiting for Browser IPC socket readiness at {socket_path}: {last_error or 'no socket'}")


def wait_for_socket_gone(socket_path: str, timeout_ms: int) -> None:
    deadline = time.monotonic() + (timeout_ms / 1000.0)
    while time.monotonic() < deadline:
        if not os.path.exists(socket_path):
            return
        time.sleep(0.25)

    if os.path.exists(socket_path):
        client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        client.settimeout(1.0)
        try:
            client.connect(socket_path)
        except OSError:
            os.unlink(socket_path)
            return
        finally:
            client.close()

    raise RuntimeError(f"Timed out waiting for Browser IPC socket removal at {socket_path}")


def wait_for_log_substring(log_path: Path, needle: str, timeout_ms: int) -> str:
    deadline = time.monotonic() + (timeout_ms / 1000.0)
    while time.monotonic() < deadline:
        text = log_path.read_text(errors="replace") if log_path.exists() else ""
        if needle in text:
            return text
        time.sleep(0.25)
    raise RuntimeError(f"Timed out waiting for {needle!r} in {log_path}")


def command_timeout_seconds(timeout_ms: int, *, minimum_seconds: float = 125.0, buffer_seconds: float = 5.0) -> float:
    return max(minimum_seconds, timeout_ms / 1000.0 + buffer_seconds)


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
def local_popup_server() -> dict[str, str]:
    webroot = Path(tempfile.mkdtemp(prefix="ghodex-browser-popup-web-"))
    main_html = """<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <title>popup-event-main</title>
  </head>
  <body>
    <h1 id="main-marker">popup-event-main</h1>
    <a id="new-tab-link" href="/child-tab.html" target="_blank" rel="opener">Open tab popup</a>
    <button id="new-window-button" type="button">Open window popup</button>
    <script>
      window.__ghodexPopupHarnessReady = true;
      document.getElementById("new-window-button").addEventListener("click", () => {
        window.open("/child-window.html", "_blank", "popup,width=420,height=320");
      });
    </script>
  </body>
</html>
"""
    child_tab_html = """<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <title>popup-child-tab</title>
  </head>
  <body>
    <h1 id="child-tab-marker">popup-child-tab</h1>
    <script>
      window.__ghodexPopupChildReady = true;
    </script>
  </body>
</html>
"""
    child_window_html = """<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <title>popup-child-window</title>
  </head>
  <body>
    <h1 id="child-window-marker">popup-child-window</h1>
    <script>
      window.__ghodexPopupChildReady = true;
    </script>
  </body>
</html>
"""

    (webroot / "index.html").write_text(main_html, encoding="utf-8")
    (webroot / "child-tab.html").write_text(child_tab_html, encoding="utf-8")
    (webroot / "child-window.html").write_text(child_window_html, encoding="utf-8")

    class QuietHandler(http.server.SimpleHTTPRequestHandler):
        def log_message(self, format: str, *args) -> None:  # noqa: A003
            return

    class ThreadedTCPServer(socketserver.ThreadingTCPServer):
        allow_reuse_address = True
        daemon_threads = True

    handler = lambda *args, **kwargs: QuietHandler(*args, directory=str(webroot), **kwargs)
    server = ThreadedTCPServer(("127.0.0.1", 0), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        port = server.server_address[1]
        yield {
            "main_url": f"http://127.0.0.1:{port}/index.html",
            "child_tab_url": f"http://127.0.0.1:{port}/child-tab.html",
            "child_window_url": f"http://127.0.0.1:{port}/child-window.html",
            "webroot": str(webroot),
        }
    finally:
        server.shutdown()
        server.server_close()
        shutil.rmtree(webroot, ignore_errors=True)


def wait_for_selector(
    socket_path: str,
    browser_tab_id: str,
    page_id: str,
    selector: str,
    timeout_ms: int,
) -> dict:
    response = send_request(
        socket_path,
        "waitForSelector",
        browser_tab_id=browser_tab_id,
        page_id=page_id,
        payload={
            "selector": selector,
            "state": "present",
            "timeoutMS": str(timeout_ms),
        },
        timeout=command_timeout_seconds(timeout_ms),
    )
    return extract_result_json(response["response"])


def wait_for_popup_event(
    socket_path: str,
    subscription_id: str,
    requested_url: str,
    timeout_ms: int,
) -> dict:
    deadline = time.monotonic() + (timeout_ms / 1000.0)
    observed = []
    while time.monotonic() < deadline:
        drain = send_request(
            socket_path,
            "drainEvents",
            payload={"subscriptionID": subscription_id, "limit": "128"},
            timeout=20.0,
        )
        result = extract_result_json(drain["response"])
        events = result["events"]
        observed.extend(events)
        for event in events:
            payload = event.get("payload", {})
            if event.get("kind") == "popupRequest" and payload.get("requestedURL") == requested_url:
                return {
                    "event": event,
                    "events": observed,
                    "drainResult": result,
                }
        time.sleep(0.25)
    raise RuntimeError(f"Timed out waiting for popupRequest event for {requested_url}")


def browser_tab_summary(socket_path: str, browser_tab_id: str) -> dict:
    tabs = extract_result_json(send_request(socket_path, "listTabs")["response"])
    for tab in tabs:
        if tab["id"] == browser_tab_id:
            return tab
    raise RuntimeError(f"Browser tab {browser_tab_id} not found")


def get_active_page(socket_path: str, browser_tab_id: str) -> dict:
    return extract_result_json(
        send_request(socket_path, "getActivePage", browser_tab_id=browser_tab_id, payload={})["response"]
    )


def list_pages(socket_path: str, browser_tab_id: str) -> list[dict]:
    return extract_result_json(
        send_request(socket_path, "listPages", browser_tab_id=browser_tab_id, payload={})["response"]
    )


def run_acceptance(args: argparse.Namespace) -> dict:
    app_bundle = Path(args.app).resolve() if args.app else resolve_default_app()
    runtime_root = str(Path(args.runtime_root).resolve())
    output_path = Path(args.output).expanduser().resolve()

    session_root = Path(f"/tmp/ghx-popupevt-{uuid.uuid4().hex[:8]}")
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
    }

    proc: subprocess.Popen[str] | None = None
    try:
        with local_popup_server() as server_info:
            artifact["server"] = server_info
            proc = launch_app(
                app_bundle,
                log_path,
                runtime_root=runtime_root,
                app_support_root=app_support_root,
                home_dir=home_dir,
            )
            artifact["pid"] = proc.pid

            artifact["stage"] = "wait_for_socket_ready"
            socket_ready = wait_for_socket_ready(str(socket_path), args.page_timeout_ms)
            artifact["socket_ready"] = socket_ready
            artifact["stage"] = "new_context"
            created_context = extract_result_json(
                send_request(
                    str(socket_path),
                    "newContext",
                    version="browser.context.v2",
                    payload={"url": server_info["main_url"]},
                    timeout=command_timeout_seconds(args.page_timeout_ms),
                )["response"]
            )
            browser_tab_id = created_context["id"]
            source_page = {
                "id": created_context["activePageID"],
                "url": created_context.get("url"),
                "title": created_context.get("title"),
            }

            artifact["stage"] = "wait_for_main_selector"
            main_ready = wait_for_selector(
                str(socket_path),
                browser_tab_id,
                source_page["id"],
                "#new-tab-link",
                args.page_timeout_ms,
            )
            wait_for_selector(
                str(socket_path),
                browser_tab_id,
                source_page["id"],
                "#new-window-button",
                args.page_timeout_ms,
            )

            artifact["stage"] = "subscribe_events"
            subscription = extract_result_json(
                send_request(
                    str(socket_path),
                    "subscribeEvents",
                    browser_tab_id=browser_tab_id,
                    payload={"kindsJSON": json.dumps(["bridgeReady", "navigationStateChanged", "popupRequest"])},
                )["response"]
            )
            subscription_id = subscription["subscriptionID"]

            artifact["stage"] = "click_new_tab"
            open_new_tab_result = extract_result_json(
                send_request(
                    str(socket_path),
                    "click",
                    browser_tab_id=browser_tab_id,
                    page_id=source_page["id"],
                    payload={"selector": "#new-tab-link", "clickMode": "trusted"},
                    timeout=max(20.0, args.page_timeout_ms / 1000.0),
                )["response"]
            )
            artifact["stage"] = "wait_for_page_tab_popup"
            page_tab_popup = wait_for_popup_event(
                str(socket_path),
                subscription_id,
                server_info["child_tab_url"],
                args.page_timeout_ms,
            )
            page_tab_event = page_tab_popup["event"]
            page_tab_payload = page_tab_event["payload"]
            page_tab_pages = list_pages(str(socket_path), browser_tab_id)

            if page_tab_payload.get("resultPageID") is None:
                raise RuntimeError("popupRequest for page-tab flow did not expose resultPageID")
            if not any(page["id"] == page_tab_payload["resultPageID"] for page in page_tab_pages):
                raise RuntimeError("popupRequest resultPageID did not resolve inside listPages")

            artifact["stage"] = "wait_for_child_tab_selector"
            child_tab_ready = wait_for_selector(
                str(socket_path),
                browser_tab_id,
                page_tab_payload["resultPageID"],
                "#child-tab-marker",
                args.page_timeout_ms,
            )

            artifact["stage"] = "click_new_window"
            open_new_window_result = extract_result_json(
                send_request(
                    str(socket_path),
                    "click",
                    browser_tab_id=browser_tab_id,
                    page_id=source_page["id"],
                    payload={"selector": "#new-window-button", "clickMode": "trusted"},
                    timeout=max(20.0, args.page_timeout_ms / 1000.0),
                )["response"]
            )
            artifact["stage"] = "wait_for_window_popup"
            window_popup = wait_for_popup_event(
                str(socket_path),
                subscription_id,
                server_info["child_window_url"],
                args.page_timeout_ms,
            )
            window_event = window_popup["event"]
            window_payload = window_event["payload"]
            artifact["stage"] = "list_tabs_after_popup"
            tabs_after_window_popup = extract_result_json(send_request(str(socket_path), "listTabs")["response"])

            if window_payload.get("routingTarget") != "popupWindowHost":
                raise RuntimeError(
                    f"popupRequest for dedicated popup host returned unexpected routingTarget: {window_payload.get('routingTarget')}"
                )
            if window_payload.get("resultBrowserTabID") is not None:
                raise RuntimeError("popupWindowHost flow unexpectedly exposed resultBrowserTabID")
            if window_payload.get("resultPageID") is not None:
                raise RuntimeError("popupWindowHost flow unexpectedly exposed resultPageID")
            if window_payload.get("resultVisibilityState") != "popupWindowForeground":
                raise RuntimeError(
                    "popupWindowHost flow did not expose popupWindowForeground visibility state"
                )

            artifact["stage"] = "finalize"
            final_drain = extract_result_json(
                send_request(
                    str(socket_path),
                    "drainEvents",
                    payload={"subscriptionID": subscription_id, "limit": "128"},
                    timeout=20.0,
                )["response"]
            )
            unsubscribe_result = extract_result_json(
                send_request(
                    str(socket_path),
                    "unsubscribeEvents",
                    browser_tab_id=browser_tab_id,
                    payload={"subscriptionID": subscription_id},
                )["response"]
            )

            artifact.update(
                {
                    "status": "passed",
                    "browserTabID": browser_tab_id,
                    "createContext": created_context,
                    "sourcePage": source_page,
                    "subscription": subscription,
                    "mainReady": main_ready,
                    "pageTabFlow": {
                        "openResult": open_new_tab_result,
                        "popupEvent": page_tab_event,
                        "pages": page_tab_pages,
                        "childReady": child_tab_ready,
                    },
                    "browserWindowFlow": {
                        "openResult": open_new_window_result,
                        "popupEvent": window_event,
                        "tabsAfterPopup": tabs_after_window_popup,
                    },
                    "finalDrain": final_drain,
                    "unsubscribeResult": unsubscribe_result,
                    "expectations": {
                        "pageTabRoutingTarget": "pageTab",
                        "browserWindowRoutingTarget": "popupWindowHost",
                    },
                }
            )
            return artifact
    except Exception as exc:  # noqa: BLE001
        artifact["status"] = "failed"
        artifact["error"] = str(exc)
        if log_path.exists():
            artifact["log_tail"] = log_path.read_text(errors="replace").splitlines()[-120:]
        return artifact
    finally:
        if proc is not None:
            try:
                terminate_process(proc)
            except Exception as exc:  # noqa: BLE001
                artifact.setdefault("cleanupErrors", []).append(f"terminate_process: {exc}")
            try:
                wait_for_socket_gone(str(socket_path), 10000)
            except Exception as exc:  # noqa: BLE001
                artifact.setdefault("cleanupErrors", []).append(f"wait_for_socket_gone: {exc}")
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(json.dumps(artifact, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        if artifact.get("status") == "passed":
            shutil.rmtree(session_root, ignore_errors=True)


def main() -> int:
    args = parse_args()
    artifact = run_acceptance(args)
    print(json.dumps(artifact, indent=2, sort_keys=True))
    return 0 if artifact.get("status") == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
