#!/usr/bin/env python3

"""
Browser runtime prompt resolution acceptance harness.

This harness launches an isolated CEF-enabled GhoDex app, serves deterministic
local permission/auth/certificate pages, exercises runtime prompt flows through
the Browser control plane, resolves them externally, and archives the observed
event envelopes plus page-visible outcomes.

Safety notes:
- the harness always launches the target app with an isolated `HOME`
- it relocates Browser runtime state through `GHODEX_BROWSER_APP_SUPPORT_ROOT`
- it never touches `/Applications/GhoDex.app` and never kills unrelated apps
"""

from __future__ import annotations

import argparse
import base64
import functools
import http.server
import json
import os
import shutil
import socket
import socketserver
import ssl
import subprocess
import tempfile
import threading
import time
import uuid
from contextlib import contextmanager
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = "/tmp/ghx-browser-runtime-prompt-resolution-acceptance.json"


class ThreadedTCPServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    allow_reuse_address = True
    daemon_threads = True


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
        description="Prove external runtime prompt resolution for permission, HTTP auth, and certificate warning flows."
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
        help="Timeout for socket, page, and runtime prompt readiness.",
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
    browser_context_id: str | None = None,
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


def extract_result_json(response: dict) -> dict | list | str | bool | int | float | None:
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
        if not isinstance(list_result, list):
            raise RuntimeError(f"Expected listContexts to return a list, got {list_result!r}")
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
def local_permission_server() -> dict[str, str]:
    webroot = Path(tempfile.mkdtemp(prefix="ghodex-browser-permission-web-"))
    main_html = """<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <title>runtime-prompt-permission</title>
  </head>
  <body>
    <h1 id="permission-ready">runtime-prompt-permission</h1>
    <button id="request-notification" type="button">Request notification permission</button>
    <pre id="permission-state"></pre>
    <script>
      window.__ghodexRuntimePromptHarness = {
        notificationSupported: typeof Notification !== "undefined",
        notificationPermission: typeof Notification !== "undefined" ? Notification.permission : "unsupported",
        notificationResult: null,
        notificationError: null
      };

      function syncPermissionState() {
        window.__ghodexRuntimePromptHarness.notificationPermission =
          typeof Notification !== "undefined" ? Notification.permission : "unsupported";
        document.getElementById("permission-state").textContent = JSON.stringify(window.__ghodexRuntimePromptHarness);
      }

      async function requestNotificationPermission() {
        syncPermissionState();
        if (typeof Notification === "undefined") {
          window.__ghodexRuntimePromptHarness.notificationError = "Notification API unavailable";
          syncPermissionState();
          return;
        }
        try {
          const result = await Notification.requestPermission();
          window.__ghodexRuntimePromptHarness.notificationResult = result;
        } catch (error) {
          window.__ghodexRuntimePromptHarness.notificationError = String(error);
        }
        syncPermissionState();
      }

      document.getElementById("request-notification").addEventListener("click", () => {
        void requestNotificationPermission();
      });

      syncPermissionState();
    </script>
  </body>
</html>
    """
    (webroot / "index.html").write_text(main_html, encoding="utf-8")
    (webroot / "blank.html").write_text(
        """<!doctype html><html><head><meta charset="utf-8"><title>runtime-prompt-blank</title></head><body></body></html>""",
        encoding="utf-8",
    )

    class QuietHandler(http.server.SimpleHTTPRequestHandler):
        protocol_version = "HTTP/1.0"

        def log_message(self, format: str, *args) -> None:  # noqa: A003
            return

    handler = functools.partial(QuietHandler, directory=str(webroot))
    with ThreadedTCPServer(("127.0.0.1", 0), handler) as server:
        port = server.server_address[1]
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            yield {
                "root": str(webroot),
                "port": str(port),
                "blank_url": f"http://127.0.0.1:{port}/blank.html",
                "index_url": f"http://127.0.0.1:{port}/index.html",
            }
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5.0)
            shutil.rmtree(webroot, ignore_errors=True)


@contextmanager
def local_auth_server() -> dict[str, str]:
    username = "ghodex-user"
    password = "ghodex-pass"
    expected = "Basic " + base64.b64encode(f"{username}:{password}".encode()).decode()
    request_log: list[dict[str, str]] = []

    class AuthHandler(http.server.BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.0"

        def log_message(self, format: str, *args) -> None:  # noqa: A003
            return

        def do_GET(self) -> None:  # noqa: N802
            request_log.append(
                {
                    "path": self.path,
                    "authorization": self.headers.get("Authorization", ""),
                }
            )
            if self.path.startswith("/favicon.ico"):
                self.send_response(204)
                self.end_headers()
                return

            if self.headers.get("Authorization") != expected:
                body = """<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <title>runtime-prompt-auth-required</title>
  </head>
  <body>
    <h1 id="auth-required">auth required</h1>
  </body>
</html>
""".encode("utf-8")
                self.send_response(401)
                self.send_header("WWW-Authenticate", 'Basic realm="GhoDex Runtime Prompt Acceptance"')
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Connection", "close")
                self.end_headers()
                self.wfile.write(body)
                return

            body = """<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <title>runtime-prompt-auth-ok</title>
  </head>
  <body>
    <h1 id="auth-ok">runtime-prompt-auth-ok</h1>
  </body>
</html>
"""
            encoded = body.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(encoded)))
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(encoded)

    with ThreadedTCPServer(("127.0.0.1", 0), AuthHandler) as server:
        port = server.server_address[1]
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            yield {
                "port": str(port),
                "protected_url": f"http://127.0.0.1:{port}/protected",
                "username": username,
                "password": password,
                "request_log": request_log,
            }
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5.0)


@contextmanager
def local_certificate_server() -> dict[str, str]:
    workroot = Path(tempfile.mkdtemp(prefix="ghodex-browser-cert-web-"))
    cert_path = workroot / "cert.pem"
    key_path = workroot / "key.pem"
    html_path = workroot / "index.html"
    html_path.write_text(
        """<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <title>runtime-prompt-cert-ok</title>
  </head>
  <body>
    <h1 id="cert-ok">runtime-prompt-cert-ok</h1>
  </body>
</html>
""",
        encoding="utf-8",
    )

    subprocess.run(
        [
            "openssl",
            "req",
            "-x509",
            "-newkey",
            "rsa:2048",
            "-keyout",
            str(key_path),
            "-out",
            str(cert_path),
            "-days",
            "1",
            "-nodes",
            "-subj",
            "/CN=localhost",
            "-addext",
            "subjectAltName=DNS:localhost,IP:127.0.0.1",
        ],
        check=True,
        capture_output=True,
        text=True,
    )

    class QuietHandler(http.server.SimpleHTTPRequestHandler):
        protocol_version = "HTTP/1.0"

        def log_message(self, format: str, *args) -> None:  # noqa: A003
            return

    handler = functools.partial(QuietHandler, directory=str(workroot))
    with ThreadedTCPServer(("127.0.0.1", 0), handler) as server:
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(certfile=str(cert_path), keyfile=str(key_path))
        server.socket = context.wrap_socket(server.socket, server_side=True)
        port = server.server_address[1]
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            yield {
                "root": str(workroot),
                "port": str(port),
                "index_url": f"https://localhost:{port}/index.html",
            }
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5.0)
            shutil.rmtree(workroot, ignore_errors=True)


def wait_for_selector(
    socket_path: str,
    browser_tab_id: str,
    page_id: str,
    selector: str,
    timeout_ms: int,
) -> dict:
    deadline = time.monotonic() + (timeout_ms / 1000.0)
    last_response: dict | None = None
    while time.monotonic() < deadline:
        remaining_ms = max(1000, int((deadline - time.monotonic()) * 1000))
        response = send_request(
            socket_path,
            "waitForSelector",
            browser_tab_id=browser_tab_id,
            page_id=page_id,
            payload={
                "selector": selector,
                "state": "present",
                "timeoutMS": str(min(remaining_ms, 5000)),
            },
            timeout=max(20.0, min(remaining_ms, 5000) / 1000.0 + 5.0),
        )
        last_response = response["response"]
        if last_response.get("ok") is True:
            return extract_result_json(last_response)

        error = last_response.get("error") or {}
        if error.get("code") not in {"bridgeUnavailable", "requestTimedOut"}:
            raise RuntimeError(f"request failed: {json.dumps(last_response, sort_keys=True)}")
        time.sleep(0.25)

    raise RuntimeError(
        f"Timed out waiting for selector {selector!r}; last={json.dumps(last_response or {}, sort_keys=True)}"
    )


def evaluate_json_string(
    socket_path: str,
    browser_tab_id: str,
    page_id: str,
    script: str,
    *,
    timeout: float = 20.0,
):
    result = extract_result_json(
        send_request(
            socket_path,
            "evaluateJavaScript",
            browser_tab_id=browser_tab_id,
            page_id=page_id,
            payload={"script": script},
            timeout=timeout,
        )["response"]
    )
    if not isinstance(result, str):
        raise RuntimeError(f"Expected a JSON string result, got: {result!r}")
    return json.loads(result)


def load_url(
    socket_path: str,
    browser_context_id: str,
    page_id: str,
    url: str,
    *,
    timeout: float,
) -> dict:
    return send_request(
        socket_path,
        "loadURL",
        version="browser.context.v2",
        browser_context_id=browser_context_id,
        page_id=page_id,
        payload={"url": url},
        timeout=timeout,
    )


def click_selector(
    socket_path: str,
    browser_tab_id: str,
    page_id: str,
    selector: str,
    *,
    click_mode: str = "trusted",
    timeout: float = 20.0,
) -> dict:
    return send_request(
        socket_path,
        "click",
        browser_tab_id=browser_tab_id,
        page_id=page_id,
        payload={
            "selector": selector,
            "clickMode": click_mode,
        },
        timeout=timeout,
    )


def wait_for_runtime_event(
    socket_path: str,
    subscription_id: str,
    *,
    kind: str,
    phase: str,
    page_id: str | None,
    request_id: str | None = None,
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
            if event.get("kind") != kind:
                continue
            payload = event.get("payload", {})
            if page_id is not None and payload.get("pageID") != page_id:
                continue
            if payload.get("phase") != phase:
                continue
            if request_id is not None and payload.get("requestID") != request_id:
                continue
            return {
                "event": event,
                "events": observed,
                "drainResult": result,
            }
        time.sleep(0.25)
    raise RuntimeError(
        f"Timed out waiting for {kind} phase={phase} requestID={request_id!r}; "
        f"observed={json.dumps(observed[-12:], sort_keys=True)}"
    )


def wait_for_harness_field(
    socket_path: str,
    browser_tab_id: str,
    page_id: str,
    *,
    field: str,
    expected_value,
    timeout_ms: int,
):
    deadline = time.monotonic() + (timeout_ms / 1000.0)
    last_value = None
    while time.monotonic() < deadline:
        state = evaluate_json_string(
            socket_path,
            browser_tab_id,
            page_id,
            "JSON.stringify(window.__ghodexRuntimePromptHarness)",
        )
        last_value = state.get(field)
        if last_value == expected_value:
            return state
        time.sleep(0.25)
    raise RuntimeError(
        f"Timed out waiting for runtime prompt harness field {field} == {expected_value!r}; last value was {last_value!r}"
    )


def expect_stale_resolution_error(response: dict, command: str) -> None:
    error = response.get("error") or {}
    error_code = error.get("code")
    if response.get("ok") is not False or error_code not in {"invalid_request", "invalidRequest"}:
        raise RuntimeError(
            f"Expected stale {command} retry to fail with invalidRequest, got {json.dumps(response, sort_keys=True)}"
        )


def main() -> int:
    args = parse_args()
    app_bundle = Path(args.app).resolve() if args.app else resolve_default_app()
    runtime_root = str(Path(args.runtime_root).resolve())

    temp_root = Path(f"/tmp/ghx-rpr-{uuid.uuid4().hex[:8]}")
    if temp_root.exists():
        shutil.rmtree(temp_root, ignore_errors=True)
    temp_root.mkdir(parents=True, exist_ok=True)
    home_dir = temp_root / "h"
    app_support_root = temp_root / "a"
    log_path = temp_root / "ghodex.log"
    socket_path = app_support_root / "browser-control.sock"
    output_path = Path(args.output)
    result = {
        "harness": "browser_runtime_prompt_resolution_acceptance",
        "app": str(app_bundle),
        "runtimeRoot": runtime_root,
        "tempRoot": str(temp_root),
        "logPath": str(log_path),
        "socketPath": str(socket_path),
        "status": "running",
    }

    proc: subprocess.Popen[str] | None = None
    subscription_id: str | None = None

    try:
        with local_permission_server() as permission_server, local_auth_server() as auth_server, local_certificate_server() as certificate_server:
            result["permissionServer"] = permission_server
            result["authServer"] = auth_server
            result["certificateServer"] = certificate_server

            proc = launch_app(
                app_bundle,
                log_path,
                runtime_root=runtime_root,
                app_support_root=app_support_root,
                home_dir=home_dir,
            )
            command_timeout = max(45.0, args.page_timeout_ms / 1000.0)
            ready_probe = wait_for_socket_ready(str(socket_path), args.page_timeout_ms)
            result["socketReadyProbe"] = ready_probe

            contexts_before = extract_result_json(ready_probe["response"])
            if not isinstance(contexts_before, list):
                raise RuntimeError(f"Expected listContexts result to be a list, got {contexts_before!r}")
            previous_context_ids = {str(context["id"]) for context in contexts_before}

            try:
                create_context = send_request(
                    str(socket_path),
                    "newContext",
                    version="browser.context.v2",
                    payload={"url": permission_server["blank_url"]},
                    timeout=command_timeout,
                )
            except TimeoutError as exc:
                create_context = {
                    "elapsed_ms": round(command_timeout * 1000, 2),
                    "request": {
                        "version": "browser.context.v2",
                        "command": "newContext",
                        "payload": {"url": permission_server["blank_url"]},
                    },
                    "response": {
                        "ok": False,
                        "error": {
                            "code": "requestTimedOut",
                            "message": str(exc),
                        },
                    },
                }
                context_summary = wait_for_new_context(str(socket_path), previous_context_ids, args.page_timeout_ms)
            else:
                if create_context["response"].get("ok") is True:
                    context_summary = extract_result_json(create_context["response"])
                else:
                    error = create_context["response"].get("error") or {}
                    if error.get("code") not in {"bridgeUnavailable", "requestTimedOut"}:
                        raise RuntimeError(
                            f"newContext failed unexpectedly: {json.dumps(create_context['response'], sort_keys=True)}"
                        )
                    context_summary = wait_for_new_context(str(socket_path), previous_context_ids, args.page_timeout_ms)

            if not isinstance(context_summary, dict):
                raise RuntimeError(f"Expected newContext result to be an object, got {context_summary!r}")

            browser_tab_id = str(context_summary["id"])
            browser_context_id = browser_tab_id
            page_id = str(context_summary["activePageID"])
            result["createContext"] = create_context
            result["contextSummary"] = context_summary
            result["initialPageBridgeReady"] = wait_for_page_bridge_ready(
                str(socket_path),
                browser_context_id=browser_context_id,
                page_id=page_id,
                timeout_ms=args.page_timeout_ms,
            )
            result["initialPermissionLoad"] = load_url(
                str(socket_path),
                browser_context_id,
                page_id,
                permission_server["index_url"],
                timeout=command_timeout,
            )
            result["initialPermissionReady"] = wait_for_selector(
                str(socket_path),
                browser_tab_id,
                page_id,
                "#permission-ready",
                args.page_timeout_ms,
            )

            subscription = extract_result_json(
                send_request(
                    str(socket_path),
                    "subscribeEvents",
                    browser_tab_id=browser_tab_id,
                    payload={
                        "kindsJSON": json.dumps(
                            [
                                "permissionRequest",
                                "authenticationRequest",
                                "certificateWarning",
                            ]
                        )
                    },
                )["response"]
            )
            if not isinstance(subscription, dict):
                raise RuntimeError(f"Expected subscribeEvents result to be an object, got {subscription!r}")
            subscription_id = str(subscription["subscriptionID"])
            result["subscription"] = subscription

            permission_state_before = evaluate_json_string(
                str(socket_path),
                browser_tab_id,
                page_id,
                "JSON.stringify(window.__ghodexRuntimePromptHarness)",
            )
            if permission_state_before.get("notificationSupported") is not True:
                raise RuntimeError(
                    "Notification API is unavailable in the Browser runtime prompt acceptance page, "
                    f"cannot exercise generic permission prompt: {json.dumps(permission_state_before, sort_keys=True)}"
                )
            result["permissionStateBefore"] = permission_state_before

            permission_click = click_selector(
                str(socket_path),
                browser_tab_id,
                page_id,
                "#request-notification",
                click_mode="trusted",
                timeout=command_timeout,
            )
            result["permissionClick"] = permission_click
            permission_requested = wait_for_runtime_event(
                str(socket_path),
                subscription_id,
                kind="permissionRequest",
                phase="requested",
                page_id=page_id,
                timeout_ms=args.page_timeout_ms,
            )
            permission_request_id = permission_requested["event"]["payload"]["requestID"]
            permission_resolve = send_request(
                str(socket_path),
                "resolvePermission",
                browser_tab_id=browser_tab_id,
                page_id=page_id,
                payload={
                    "requestID": permission_request_id,
                    "result": "allow",
                },
                timeout=command_timeout,
            )
            permission_resolve_ack = extract_result_json(permission_resolve["response"])
            permission_resolved = wait_for_runtime_event(
                str(socket_path),
                subscription_id,
                kind="permissionRequest",
                phase="resolved",
                page_id=page_id,
                request_id=permission_request_id,
                timeout_ms=args.page_timeout_ms,
            )
            permission_state_after = wait_for_harness_field(
                str(socket_path),
                browser_tab_id,
                page_id,
                field="notificationResult",
                expected_value="granted",
                timeout_ms=args.page_timeout_ms,
            )
            stale_permission_retry = send_request(
                str(socket_path),
                "resolvePermission",
                browser_tab_id=browser_tab_id,
                page_id=page_id,
                payload={
                    "requestID": permission_request_id,
                    "result": "allow",
                },
                timeout=command_timeout,
            )
            expect_stale_resolution_error(stale_permission_retry["response"], "resolvePermission")

            result["permissionFlow"] = {
                "click": permission_click,
                "requested": permission_requested,
                "resolve": permission_resolve,
                "resolveAck": permission_resolve_ack,
                "resolved": permission_resolved,
                "stateAfter": permission_state_after,
                "staleRetry": stale_permission_retry,
            }

            auth_load = load_url(
                str(socket_path),
                browser_context_id,
                page_id,
                auth_server["protected_url"],
                timeout=command_timeout,
            )
            auth_requested = wait_for_runtime_event(
                str(socket_path),
                subscription_id,
                kind="authenticationRequest",
                phase="requested",
                page_id=None,
                timeout_ms=args.page_timeout_ms,
            )
            auth_request_id = auth_requested["event"]["payload"]["requestID"]
            auth_resolve = send_request(
                str(socket_path),
                "resolveAuth",
                browser_tab_id=browser_tab_id,
                page_id=page_id,
                payload={
                    "requestID": auth_request_id,
                    "accepted": "true",
                    "username": auth_server["username"],
                    "password": auth_server["password"],
                },
                timeout=command_timeout,
            )
            auth_resolve_ack = extract_result_json(auth_resolve["response"])
            auth_resolved = wait_for_runtime_event(
                str(socket_path),
                subscription_id,
                kind="authenticationRequest",
                phase="resolved",
                page_id=None,
                request_id=auth_request_id,
                timeout_ms=args.page_timeout_ms,
            )
            auth_ready = wait_for_selector(
                str(socket_path),
                browser_tab_id,
                page_id,
                "#auth-ok",
                args.page_timeout_ms,
            )
            auth_marker = extract_result_json(
                send_request(
                    str(socket_path),
                    "getText",
                    browser_tab_id=browser_tab_id,
                    page_id=page_id,
                    payload={"selector": "#auth-ok"},
                    timeout=command_timeout,
                )["response"]
            )
            stale_auth_retry = send_request(
                str(socket_path),
                "resolveAuth",
                browser_tab_id=browser_tab_id,
                page_id=page_id,
                payload={
                    "requestID": auth_request_id,
                    "accepted": "true",
                    "username": auth_server["username"],
                    "password": auth_server["password"],
                },
                timeout=command_timeout,
            )
            expect_stale_resolution_error(stale_auth_retry["response"], "resolveAuth")

            result["authFlow"] = {
                "loadURL": auth_load,
                "requested": auth_requested,
                "resolve": auth_resolve,
                "resolveAck": auth_resolve_ack,
                "resolved": auth_resolved,
                "ready": auth_ready,
                "marker": auth_marker,
                "staleRetry": stale_auth_retry,
            }

            certificate_load = load_url(
                str(socket_path),
                browser_context_id,
                page_id,
                certificate_server["index_url"],
                timeout=command_timeout,
            )
            certificate_requested = wait_for_runtime_event(
                str(socket_path),
                subscription_id,
                kind="certificateWarning",
                phase="requested",
                page_id=None,
                timeout_ms=args.page_timeout_ms,
            )
            certificate_request_id = certificate_requested["event"]["payload"]["requestID"]
            certificate_resolve = send_request(
                str(socket_path),
                "resolveCertificate",
                browser_tab_id=browser_tab_id,
                page_id=page_id,
                payload={
                    "requestID": certificate_request_id,
                    "accepted": "true",
                },
                timeout=command_timeout,
            )
            certificate_resolve_ack = extract_result_json(certificate_resolve["response"])
            certificate_resolved = wait_for_runtime_event(
                str(socket_path),
                subscription_id,
                kind="certificateWarning",
                phase="resolved",
                page_id=None,
                request_id=certificate_request_id,
                timeout_ms=args.page_timeout_ms,
            )
            certificate_ready = wait_for_selector(
                str(socket_path),
                browser_tab_id,
                page_id,
                "#cert-ok",
                args.page_timeout_ms,
            )
            certificate_marker = extract_result_json(
                send_request(
                    str(socket_path),
                    "getText",
                    browser_tab_id=browser_tab_id,
                    page_id=page_id,
                    payload={"selector": "#cert-ok"},
                    timeout=command_timeout,
                )["response"]
            )
            stale_certificate_retry = send_request(
                str(socket_path),
                "resolveCertificate",
                browser_tab_id=browser_tab_id,
                page_id=page_id,
                payload={
                    "requestID": certificate_request_id,
                    "accepted": "true",
                },
                timeout=command_timeout,
            )
            expect_stale_resolution_error(stale_certificate_retry["response"], "resolveCertificate")

            result["certificateFlow"] = {
                "loadURL": certificate_load,
                "requested": certificate_requested,
                "resolve": certificate_resolve,
                "resolveAck": certificate_resolve_ack,
                "resolved": certificate_resolved,
                "ready": certificate_ready,
                "marker": certificate_marker,
                "staleRetry": stale_certificate_retry,
            }

            if subscription_id is not None:
                result["unsubscribe"] = send_request(
                    str(socket_path),
                    "unsubscribeEvents",
                    browser_tab_id=browser_tab_id,
                    payload={"subscriptionID": subscription_id},
                    timeout=command_timeout,
                )
                subscription_id = None

            result["status"] = "passed"
    except Exception as exc:  # noqa: BLE001
        result["status"] = "failed"
        result["error"] = str(exc)
        if log_path.exists():
            result["logTail"] = log_path.read_text(encoding="utf-8", errors="replace")[-16000:]
        raise
    finally:
        if subscription_id is not None and socket_path.exists():
            try:
                result["unsubscribe"] = send_request(
                    str(socket_path),
                    "unsubscribeEvents",
                    payload={"subscriptionID": subscription_id},
                    timeout=10.0,
                )
            except Exception as exc:  # noqa: BLE001
                result["unsubscribeError"] = str(exc)

        if proc is not None:
            try:
                terminate_process(proc)
            finally:
                try:
                    wait_for_socket_gone(str(socket_path), 10000)
                except Exception as exc:  # noqa: BLE001
                    result["socketCleanupError"] = str(exc)

        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(json.dumps(result, indent=2, sort_keys=True), encoding="utf-8")
        shutil.rmtree(temp_root, ignore_errors=True)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
