#!/usr/bin/env python3

"""
Control Harness canonical browser protocol surface live acceptance harness.

This harness launches an isolated CEF-enabled GhoDex.app and proves the public
browser-facing Control Harness commands against the `+control` socket using the
canonical `browser.*` command names.

Covered surfaces:

- browser.tab.*
- browser.context.*
- browser.page.*
- browser.frame.list
- browser.debug.status
- browser.cookie.*
- browser.dom.*
- browser.event.*
- browser.prompt.resolveDialog
- browser.prompt.resolvePermission
- browser.prompt.resolveAuth
- browser.prompt.resolveCertificate
- browser.download.cancel
"""

from __future__ import annotations

import argparse
import base64
import functools
import http.server
import json
import os
import re
import shutil
import signal
import socket
import socketserver
import ssl
import subprocess
import tempfile
import threading
import time
import uuid
from contextlib import ExitStack, contextmanager
from pathlib import Path
from typing import Any, Callable


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = "/tmp/ghx-control-harness-browser-protocol-surface-live-acceptance.json"
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
    raise SystemExit("No default CEF runtime root found. Pass --runtime-root=/path/to/runtime.")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Prove canonical browser.* Control Harness commands against a live GhoDex app."
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
        default=45000,
        help="Timeout budget for app launch and harness socket discovery.",
    )
    parser.add_argument(
        "--page-timeout-ms",
        type=int,
        default=90000,
        help="Timeout budget for bridge readiness, navigation, and runtime browser events.",
    )
    parser.add_argument(
        "--request-timeout",
        type=float,
        default=None,
        help="Per-request transport timeout in seconds. Defaults to a browser-bridge-safe value.",
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


def command_timeout_seconds(
    timeout_ms: int,
    *,
    minimum_seconds: float = 125.0,
    buffer_seconds: float = 5.0,
) -> float:
    return max(minimum_seconds, timeout_ms / 1000.0 + buffer_seconds)


def send_single_request(socket_path: str, body: dict[str, Any], *, timeout: float) -> dict[str, Any]:
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        client.settimeout(timeout)
        client.connect(socket_path)
        client.sendall((json.dumps(body) + "\n").encode())
        client.shutdown(socket.SHUT_WR)
        response_text = recv_until_close(client)
    finally:
        client.close()
    return json.loads(response_text)


def write_artifact(output_path: Path, artifact: dict[str, Any]) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(artifact, indent=2, sort_keys=True), encoding="utf-8")


def tail_text(path: Path, *, max_lines: int = 120) -> list[str]:
    if not path.exists():
        return []
    try:
        return path.read_text(encoding="utf-8", errors="replace").splitlines()[-max_lines:]
    except OSError:
        return []


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


def terminate_process(proc: subprocess.Popen[str], timeout: float = 20.0) -> None:
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
    env["GHODEX_SKIP_INITIAL_TERMINAL_WINDOW"] = "1"
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
            # Some successful probes legitimately return empty containers,
            # such as an empty context/page list after teardown completes.
            if value is not None:
                return value
        except Exception as exc:  # noqa: BLE001
            last_error = str(exc)
        time.sleep(interval_s)
    raise RuntimeError(f"Timed out waiting for {description}. Last error: {last_error or 'none'}")


class HarnessClient:
    def __init__(self, socket_path: str, *, timeout: float, artifact: dict[str, Any]):
        self.socket_path = socket_path
        self.timeout = timeout
        self.artifact = artifact
        self.artifact.setdefault("requests", {})
        self.artifact.setdefault("request_order", [])
        self._event_buffer: dict[tuple[str, str], list[dict[str, Any]]] = {}
        self._event_drain_count = 0

    def request(
        self,
        command: str,
        *,
        allow_error: bool = False,
        label: str | None = None,
        timeout: float | None = None,
        **fields: Any,
    ) -> dict[str, Any]:
        request_label = label or command
        body: dict[str, Any] = {
            "request_id": f"req-{uuid.uuid4().hex[:12]}",
            "command": command,
        }
        for key, value in fields.items():
            if value is not None:
                body[key] = value

        response = send_single_request(self.socket_path, body, timeout=timeout or self.timeout)
        self.artifact["request_order"].append(request_label)
        self.artifact["requests"][request_label] = {
            "request": body,
            "response": response,
        }
        if response.get("status") != "ok" and not allow_error:
            raise RuntimeError(
                f"{command} failed: {json.dumps(response, ensure_ascii=False, sort_keys=True)}"
            )
        return response

    def pop_buffered_event(
        self,
        *,
        browser_tab_id: str,
        subscription_id: str,
        kind: str,
        predicate: Callable[[dict[str, Any]], bool] | None = None,
        label: str,
    ) -> dict[str, Any] | None:
        buffer_key = (browser_tab_id, subscription_id)
        buffered_events = self._event_buffer.setdefault(buffer_key, [])
        for index, buffered in enumerate(buffered_events):
            event = buffered["event"]
            if event.get("kind") != kind:
                continue
            if predicate is not None and not predicate(event):
                continue
            return buffered_events.pop(index)

        self._event_drain_count += 1
        try:
            response = self.request(
                "browser.event.drain",
                label=f"{label}.drain.{self._event_drain_count}",
                browser_tab_id=browser_tab_id,
                payload={"subscriptionID": subscription_id, "limit": "128"},
                timeout=min(2.0, self.timeout),
            )
        except TimeoutError:
            return None
        except socket.timeout:
            return None
        result = response.get("result") or {}
        for event in result.get("events") or []:
            buffered_events.append(
                {
                    "event": event,
                    "drain": result,
                }
            )

        for index, buffered in enumerate(buffered_events):
            event = buffered["event"]
            if event.get("kind") != kind:
                continue
            if predicate is not None and not predicate(event):
                continue
            return buffered_events.pop(index)

        return None


class ThreadedTCPServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


@contextmanager
def local_browser_fixture_server() -> dict[str, Any]:
    webroot = Path(tempfile.mkdtemp(prefix="ghx-control-browser-web-"))
    download_state: dict[str, Any] = {
        "requests": [],
        "bytes_sent": 0,
        "completed": False,
    }

    index_html = """<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <title>control-browser-index</title>
  </head>
  <body>
    <h1 id="ready-marker" data-route="index">control-browser-index</h1>
    <div id="status">idle</div>
    <input id="name-input" value="" />
    <button id="click-target" data-role="action" onclick="document.getElementById('status').textContent='clicked';">Click Me</button>
    <button id="request-notification" type="button">Request notification permission</button>
    <button id="trigger-alert" type="button">Trigger alert</button>
    <button id="trigger-confirm" type="button">Trigger confirm</button>
    <button id="trigger-prompt" type="button">Trigger prompt</button>
    <a id="second-link" href="/second.html">Go second</a>
    <a id="download-link" href="/download.bin" download="fixture.bin">Download fixture</a>
    <pre id="state-json"></pre>
    <script>
      window.__ghxHarness = {
        alertDone: false,
        confirmResult: null,
        promptResult: null,
        notificationSupported: typeof Notification !== "undefined",
        notificationPermission: typeof Notification !== "undefined" ? Notification.permission : "unsupported",
        notificationResult: null,
        notificationError: null
      };

      function syncState() {
        window.__ghxHarness.notificationPermission =
          typeof Notification !== "undefined" ? Notification.permission : "unsupported";
        document.getElementById("state-json").textContent = JSON.stringify(window.__ghxHarness);
      }

      window.__ghxScheduleAlert = function() {
        setTimeout(() => {
          alert("Harness alert");
          window.__ghxHarness.alertDone = true;
          document.getElementById("status").textContent = "alert-done";
          syncState();
        }, 0);
      };

      window.__ghxScheduleConfirm = function() {
        setTimeout(() => {
          window.__ghxHarness.confirmResult = confirm("Harness confirm?");
          document.getElementById("status").textContent = "confirm:" + String(window.__ghxHarness.confirmResult);
          syncState();
        }, 0);
      };

      window.__ghxSchedulePrompt = function() {
        setTimeout(() => {
          window.__ghxHarness.promptResult = prompt("Harness prompt?", "anon");
          document.getElementById("status").textContent = "prompt:" + String(window.__ghxHarness.promptResult);
          syncState();
        }, 0);
      };

      window.__ghxRequestNotification = async function() {
        syncState();
        if (typeof Notification === "undefined") {
          window.__ghxHarness.notificationError = "Notification API unavailable";
          syncState();
          return "unsupported";
        }
        try {
          const result = await Notification.requestPermission();
          window.__ghxHarness.notificationResult = result;
        } catch (error) {
          window.__ghxHarness.notificationError = String(error);
        }
        syncState();
        return window.__ghxHarness.notificationResult;
      };

      document.getElementById("request-notification").addEventListener("click", () => {
        void window.__ghxRequestNotification();
      });
      document.getElementById("trigger-alert").addEventListener("click", () => window.__ghxScheduleAlert());
      document.getElementById("trigger-confirm").addEventListener("click", () => window.__ghxScheduleConfirm());
      document.getElementById("trigger-prompt").addEventListener("click", () => window.__ghxSchedulePrompt());
      syncState();
    </script>
  </body>
</html>
"""
    second_html = """<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <title>control-browser-second</title>
  </head>
  <body>
    <h1 id="second-marker" data-route="second">control-browser-second</h1>
    <a id="index-link" href="/index.html">Back index</a>
  </body>
</html>
"""
    (webroot / "index.html").write_text(index_html, encoding="utf-8")
    (webroot / "second.html").write_text(second_html, encoding="utf-8")
    (webroot / "favicon.ico").write_bytes(b"")

    class FixtureHandler(http.server.SimpleHTTPRequestHandler):
        protocol_version = "HTTP/1.0"

        def log_message(self, format: str, *args) -> None:  # noqa: A003
            return

        def do_GET(self) -> None:  # noqa: N802
            if self.path.startswith("/download.bin"):
                self.send_download()
                return
            super().do_GET()

        def send_download(self) -> None:
            size = 6 * 1024 * 1024
            chunk = b"x" * 65536
            download_state["requests"].append({"path": self.path, "size": size})
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Disposition", 'attachment; filename="fixture.bin"')
            self.send_header("Content-Length", str(size))
            self.send_header("Connection", "close")
            self.end_headers()

            sent = 0
            try:
                while sent < size:
                    remaining = size - sent
                    payload = chunk[: min(len(chunk), remaining)]
                    self.wfile.write(payload)
                    self.wfile.flush()
                    sent += len(payload)
                    download_state["bytes_sent"] = sent
                    time.sleep(0.03)
                download_state["completed"] = True
            except (BrokenPipeError, ConnectionResetError):
                download_state["bytes_sent"] = sent

    handler = functools.partial(FixtureHandler, directory=str(webroot))
    with ThreadedTCPServer(("127.0.0.1", 0), handler) as server:
        port = server.server_address[1]
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            yield {
                "root": str(webroot),
                "port": str(port),
                "index_url": f"http://127.0.0.1:{port}/index.html",
                "second_url": f"http://127.0.0.1:{port}/second.html",
                "download_url": f"http://127.0.0.1:{port}/download.bin",
                "download_state": download_state,
            }
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5.0)
            shutil.rmtree(webroot, ignore_errors=True)


@contextmanager
def local_auth_server() -> dict[str, Any]:
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
  <head><meta charset="utf-8"><title>runtime-prompt-auth-required</title></head>
  <body><h1 id="auth-required">auth required</h1></body>
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
  <head><meta charset="utf-8"><title>runtime-prompt-auth-ok</title></head>
  <body><h1 id="auth-ok">runtime-prompt-auth-ok</h1></body>
</html>
""".encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(body)

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
def local_certificate_server() -> dict[str, Any]:
    workroot = Path(tempfile.mkdtemp(prefix="ghx-control-browser-cert-"))
    cert_path = workroot / "cert.pem"
    key_path = workroot / "key.pem"
    index_path = workroot / "index.html"
    index_path.write_text(
        """<!doctype html>
<html>
  <head><meta charset="utf-8"><title>runtime-prompt-cert-ok</title></head>
  <body><h1 id="cert-ok">runtime-prompt-cert-ok</h1></body>
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
    client: HarnessClient,
    *,
    browser_tab_id: str,
    page_id: str,
    selector: str,
    timeout_ms: int,
    label: str,
) -> dict[str, Any]:
    def predicate() -> dict[str, Any] | None:
        response = client.request(
            "browser.dom.waitFor",
            allow_error=True,
            label=f"{label}.probe",
            browser_tab_id=browser_tab_id,
            page_id=page_id,
            payload={
                "selector": selector,
                "state": "present",
                "timeoutMS": "1500",
            },
        )
        if response.get("status") == "ok":
            return response.get("result")
        if response.get("error_code") not in {"operation_failed", "control_unavailable"}:
            raise RuntimeError(json.dumps(response, ensure_ascii=False, sort_keys=True))
        return None

    return wait_until(f"selector {selector}", predicate, timeout_ms=timeout_ms)


def wait_for_context_summary(
    client: HarnessClient,
    *,
    browser_context_id: str,
    timeout_ms: int,
    label: str,
) -> dict[str, Any]:
    return wait_until(
        f"context {browser_context_id}",
        lambda: client.request(
            "browser.context.get",
            allow_error=True,
            label=f"{label}.probe",
            browser_context_id=browser_context_id,
        ).get("result"),
        timeout_ms=timeout_ms,
    )


def wait_for_context_absent(
    client: HarnessClient,
    *,
    browser_context_id: str,
    timeout_ms: int,
    label: str,
) -> list[dict[str, Any]]:
    def predicate() -> list[dict[str, Any]] | None:
        response = client.request("browser.context.list", label=f"{label}.list")
        contexts = response.get("result") or []
        return contexts if all(str(context.get("id")) != browser_context_id for context in contexts) else None

    return wait_until(f"context {browser_context_id} absent", predicate, timeout_ms=timeout_ms)


def wait_for_page_summary(
    client: HarnessClient,
    *,
    browser_context_id: str,
    page_id: str,
    timeout_ms: int,
    label: str,
) -> dict[str, Any]:
    def predicate() -> dict[str, Any] | None:
        pages = client.request(
            "browser.page.list",
            label=f"{label}.pages",
            browser_context_id=browser_context_id,
        ).get("result") or []
        for page in pages:
            if str(page.get("id")) == page_id:
                return page
        return None

    return wait_until(f"page {page_id}", predicate, timeout_ms=timeout_ms)


def wait_for_page_absent(
    client: HarnessClient,
    *,
    browser_context_id: str,
    page_id: str,
    timeout_ms: int,
    label: str,
) -> list[dict[str, Any]]:
    def predicate() -> list[dict[str, Any]] | None:
        pages = client.request(
            "browser.page.list",
            label=f"{label}.pages",
            browser_context_id=browser_context_id,
        ).get("result") or []
        return pages if all(str(page.get("id")) != page_id for page in pages) else None

    return wait_until(f"page {page_id} absent", predicate, timeout_ms=timeout_ms)


def wait_for_active_page(
    client: HarnessClient,
    *,
    browser_context_id: str,
    expected_page_id: str,
    timeout_ms: int,
    label: str,
) -> dict[str, Any]:
    def predicate() -> dict[str, Any] | None:
        response = client.request(
            "browser.page.getActive",
            label=f"{label}.active",
            browser_context_id=browser_context_id,
        )
        page = response.get("result")
        if str(page.get("id")) == expected_page_id:
            return page
        return None

    return wait_until(
        f"active page {expected_page_id}",
        predicate,
        timeout_ms=timeout_ms,
    )


def wait_for_event(
    client: HarnessClient,
    *,
    browser_tab_id: str,
    subscription_id: str,
    kind: str,
    timeout_ms: int,
    label: str,
    predicate: Callable[[dict[str, Any]], bool] | None = None,
) -> dict[str, Any]:
    def inner() -> dict[str, Any] | None:
        return client.pop_buffered_event(
            browser_tab_id=browser_tab_id,
            subscription_id=subscription_id,
            kind=kind,
            predicate=predicate,
            label=label,
        )

    return wait_until(f"event {kind}", inner, timeout_ms=timeout_ms)


def wait_for_browser_control_responsive(
    client: HarnessClient,
    *,
    browser_context_id: str,
    timeout_ms: int,
    required_successes: int = 3,
    label: str,
) -> list[dict[str, Any]]:
    probes: list[dict[str, Any]] = []

    def predicate() -> list[dict[str, Any]] | None:
        response = client.request(
            "browser.page.getActive",
            allow_error=True,
            label=f"{label}.probe",
            browser_context_id=browser_context_id,
        )
        if response.get("status") == "ok":
            probes.append(response.get("result"))
            return probes if len(probes) >= required_successes else None
        probes.clear()
        return None

    return wait_until(
        "browser control responsiveness",
        predicate,
        timeout_ms=timeout_ms,
        interval_s=0.25,
    )


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


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
    runtime_root = Path(args.runtime_root).resolve() if args.runtime_root else resolve_default_runtime_root()
    output_path = Path(args.output).expanduser().resolve()

    session_root = Path(f"/tmp/ghx-control-harness-browser-protocol-{uuid.uuid4().hex[:8]}")
    home_dir = session_root / "home"
    app_support_root = session_root / "app-support"
    config_path = home_dir / ".config" / "ghostty" / "config"
    log_path = session_root / "app.log"

    artifact: dict[str, Any] = {
        "app": str(app_bundle),
        "runtime_root": str(runtime_root),
        "session_root": str(session_root),
        "log_path": str(log_path),
        "verified_command_families": [
            "browser.tab",
            "browser.context",
            "browser.page",
            "browser.frame",
            "browser.debug",
            "browser.cookie",
            "browser.dom",
            "browser.event",
            "browser.prompt",
            "browser.download",
        ],
        "summary": {},
    }
    request_timeout = args.request_timeout or command_timeout_seconds(args.page_timeout_ms)
    artifact["request_timeout_seconds"] = request_timeout

    proc: subprocess.Popen[str] | None = None
    skip_cleanup = False

    try:
        with ExitStack() as stack:
            fixture_server = stack.enter_context(local_browser_fixture_server())
            auth_server = stack.enter_context(local_auth_server())
            cert_server = stack.enter_context(local_certificate_server())
            compat_cert_server = stack.enter_context(local_certificate_server())
            artifact["servers"] = {
                "fixture": {
                    "index_url": fixture_server["index_url"],
                    "second_url": fixture_server["second_url"],
                    "download_url": fixture_server["download_url"],
                },
                "auth": {"protected_url": auth_server["protected_url"]},
                "certificate": {"index_url": cert_server["index_url"]},
                "compat_certificate": {"index_url": compat_cert_server["index_url"]},
            }

            proc = launch_app(
                app_bundle,
                log_path,
                runtime_root=runtime_root,
                app_support_root=app_support_root,
                home_dir=home_dir,
                config_path=config_path,
            )
            artifact["pid"] = proc.pid
            socket_path = wait_for_harness_socket(proc.pid, timeout_ms=args.startup_timeout_ms)
            artifact["socket_path"] = socket_path
            client = HarnessClient(socket_path, timeout=request_timeout, artifact=artifact)

            artifact["handshake"] = client.request("system.handshake", label="system.handshake")

            initial_contexts = client.request("browser.context.list", label="browser.context.list.initial")
            require(initial_contexts.get("status") == "ok", "initial browser.context.list failed")

            create_context_response = client.request(
                "browser.context.new",
                allow_error=True,
                label="browser.context.new.main",
                payload={"url": fixture_server["index_url"]},
            )
            if create_context_response.get("status") == "ok":
                main_context = create_context_response["result"]
            else:
                previous_ids = {
                    str(context.get("id"))
                    for context in (initial_contexts.get("result") or [])
                }

                def discover_created_context() -> dict[str, Any] | None:
                    contexts = client.request(
                        "browser.context.list",
                        label="browser.context.list.discovery",
                    ).get("result") or []
                    for context in contexts:
                        context_id = str(context.get("id"))
                        if context_id and context_id not in previous_ids:
                            return context
                    return None

                main_context = wait_until(
                    "main browser context creation",
                    discover_created_context,
                    timeout_ms=args.page_timeout_ms,
                )

            main_context_id = str(main_context["id"])
            main_page_id = str(main_context["activePageID"])

            wait_for_context_summary(
                client,
                browser_context_id=main_context_id,
                timeout_ms=args.page_timeout_ms,
                label="main-context",
            )
            wait_for_selector(
                client,
                browser_tab_id=main_context_id,
                page_id=main_page_id,
                selector="#ready-marker",
                timeout_ms=args.page_timeout_ms,
                label="main-ready",
            )

            debug_status = client.request(
                "browser.debug.status",
                label="browser.debug.status.after-create",
            )
            context_get = client.request(
                "browser.context.get",
                browser_context_id=main_context_id,
                label="browser.context.get.main",
            )
            page_get_active = client.request(
                "browser.page.getActive",
                browser_context_id=main_context_id,
                label="browser.page.getActive.main",
            )
            page_list = client.request(
                "browser.page.list",
                browser_context_id=main_context_id,
                label="browser.page.list.main",
            )
            frame_list = client.request(
                "browser.frame.list",
                browser_context_id=main_context_id,
                page_id=main_page_id,
                label="browser.frame.list.main",
            )
            tab_list_initial = client.request(
                "browser.tab.list",
                label="browser.tab.list.initial",
            )

            compat_tab = client.request(
                "browser.tab.new",
                label="browser.tab.new.compat",
                payload={"url": fixture_server["second_url"]},
            )["result"]
            compat_tab_id = str(compat_tab["id"])
            compat_context_summary = wait_for_context_summary(
                client,
                browser_context_id=compat_tab_id,
                timeout_ms=args.page_timeout_ms,
                label="compat-context",
            )
            compat_page_id = str(compat_context_summary["activePageID"])
            wait_for_selector(
                client,
                browser_tab_id=compat_tab_id,
                page_id=compat_page_id,
                selector="#second-marker",
                timeout_ms=args.page_timeout_ms,
                label="compat-ready",
            )

            activate_context = client.request(
                "browser.context.activate",
                browser_context_id=main_context_id,
                label="browser.context.activate.main",
            )
            active_main_context = wait_until(
                "main context frontmost",
                lambda: (
                    response.get("result")
                    if (response := client.request(
                        "browser.context.get",
                        browser_context_id=main_context_id,
                        label="browser.context.get.frontmost",
                    )).get("result", {}).get("isFrontmost") is True
                    else None
                ),
                timeout_ms=args.page_timeout_ms,
            )

            new_page = client.request(
                "browser.page.new",
                browser_context_id=main_context_id,
                label="browser.page.new.extra",
                payload={"url": fixture_server["second_url"]},
            )["result"]
            extra_page_id = str(new_page["id"])
            wait_for_selector(
                client,
                browser_tab_id=main_context_id,
                page_id=extra_page_id,
                selector="#second-marker",
                timeout_ms=args.page_timeout_ms,
                label="extra-page-ready",
            )
            page_list_with_extra = client.request(
                "browser.page.list",
                browser_context_id=main_context_id,
                label="browser.page.list.with-extra",
            )
            activate_main_page = client.request(
                "browser.page.activate",
                browser_context_id=main_context_id,
                page_id=main_page_id,
                label="browser.page.activate.main",
            )
            wait_for_active_page(
                client,
                browser_context_id=main_context_id,
                expected_page_id=main_page_id,
                timeout_ms=args.page_timeout_ms,
                label="main-page-active",
            )

            load_second = client.request(
                "browser.page.load",
                browser_context_id=main_context_id,
                page_id=main_page_id,
                label="browser.page.load.second",
                payload={"url": fixture_server["second_url"]},
            )
            wait_for_selector(
                client,
                browser_tab_id=main_context_id,
                page_id=main_page_id,
                selector="#second-marker",
                timeout_ms=args.page_timeout_ms,
                label="main-loaded-second",
            )
            page_back = client.request(
                "browser.page.back",
                browser_context_id=main_context_id,
                page_id=main_page_id,
                label="browser.page.back.main",
            )
            wait_for_selector(
                client,
                browser_tab_id=main_context_id,
                page_id=main_page_id,
                selector="#ready-marker",
                timeout_ms=args.page_timeout_ms,
                label="main-back-index",
            )
            page_forward = client.request(
                "browser.page.forward",
                browser_context_id=main_context_id,
                page_id=main_page_id,
                label="browser.page.forward.main",
            )
            wait_for_selector(
                client,
                browser_tab_id=main_context_id,
                page_id=main_page_id,
                selector="#second-marker",
                timeout_ms=args.page_timeout_ms,
                label="main-forward-second",
            )
            page_reload = client.request(
                "browser.page.reload",
                browser_context_id=main_context_id,
                page_id=main_page_id,
                label="browser.page.reload.main",
            )
            wait_for_selector(
                client,
                browser_tab_id=main_context_id,
                page_id=main_page_id,
                selector="#second-marker",
                timeout_ms=args.page_timeout_ms,
                label="main-reload-second",
            )
            event_subscription = client.request(
                "browser.event.subscribe",
                browser_tab_id=main_context_id,
                label="browser.event.subscribe.main",
                payload={
                    "kindsJSON": json.dumps(
                        [
                            "navigationStateChanged",
                            "pageInspectionSnapshot",
                            "download",
                            "javaScriptDialog",
                            "permissionRequest",
                            "authenticationRequest",
                            "certificateWarning",
                        ]
                    )
                },
            )["result"]
            subscription_id = str(event_subscription["subscriptionID"])
            client.request(
                "browser.event.drain",
                browser_tab_id=main_context_id,
                label="browser.event.drain.clear",
                payload={"subscriptionID": subscription_id, "limit": "128"},
            )

            load_index = client.request(
                "browser.page.load",
                browser_context_id=main_context_id,
                page_id=main_page_id,
                label="browser.page.load.index",
                payload={"url": fixture_server["index_url"]},
            )
            wait_for_selector(
                client,
                browser_tab_id=main_context_id,
                page_id=main_page_id,
                selector="#ready-marker",
                timeout_ms=args.page_timeout_ms,
                label="main-return-index",
            )

            dom_query = client.request(
                "browser.dom.query",
                browser_tab_id=main_context_id,
                page_id=main_page_id,
                label="browser.dom.query.click-target",
                payload={"selector": "#click-target"},
            )
            dom_click = client.request(
                "browser.dom.click",
                browser_tab_id=main_context_id,
                page_id=main_page_id,
                label="browser.dom.click.click-target",
                payload={"selector": "#click-target", "clickMode": "trusted"},
            )
            dom_type = client.request(
                "browser.dom.type",
                browser_tab_id=main_context_id,
                page_id=main_page_id,
                label="browser.dom.type.name-input",
                payload={"selector": "#name-input", "text": "Leon"},
            )
            dom_get_text = client.request(
                "browser.dom.getText",
                browser_tab_id=main_context_id,
                page_id=main_page_id,
                label="browser.dom.getText.status",
                payload={"selector": "#status"},
            )
            dom_get_attributes = client.request(
                "browser.dom.getAttributes",
                browser_tab_id=main_context_id,
                page_id=main_page_id,
                label="browser.dom.getAttributes.click-target",
                payload={"selector": "#click-target"},
            )
            dom_get_bounding_box = client.request(
                "browser.dom.getBoundingBox",
                browser_tab_id=main_context_id,
                page_id=main_page_id,
                label="browser.dom.getBoundingBox.click-target",
                payload={"selector": "#click-target"},
            )
            dom_snapshot = client.request(
                "browser.dom.snapshot",
                browser_tab_id=main_context_id,
                page_id=main_page_id,
                label="browser.dom.snapshot.body",
                payload={"selector": "body", "maxDepth": "2", "includeText": "true"},
            )
            batch_commands = [
                {
                    "id": str(uuid.uuid4()),
                    "command": "query",
                    "selector": "#click-target",
                },
                {
                    "id": str(uuid.uuid4()),
                    "command": "getText",
                    "selector": "#status",
                },
                {
                    "id": str(uuid.uuid4()),
                    "command": "getAttributes",
                    "selector": "#click-target",
                },
                {
                    "id": str(uuid.uuid4()),
                    "command": "getBoundingBox",
                    "selector": "#click-target",
                },
            ]
            dom_batch = client.request(
                "browser.dom.batch",
                browser_tab_id=main_context_id,
                page_id=main_page_id,
                label="browser.dom.batch.main",
                payload={"commandsJSON": json.dumps(batch_commands)},
            )
            dom_eval = client.request(
                "browser.dom.eval",
                browser_tab_id=main_context_id,
                page_id=main_page_id,
                label="browser.dom.eval.state",
                payload={"script": "JSON.stringify(window.__ghxHarness)"},
            )

            nav_event = wait_for_event(
                client,
                browser_tab_id=main_context_id,
                subscription_id=subscription_id,
                kind="navigationStateChanged",
                timeout_ms=args.page_timeout_ms,
                label="navigation-event",
                predicate=lambda event: event.get("payload", {}).get("url") == fixture_server["index_url"]
                and event.get("payload", {}).get("isLoading") == "false",
            )

            page_inspection_event = wait_for_event(
                client,
                browser_tab_id=main_context_id,
                subscription_id=subscription_id,
                kind="pageInspectionSnapshot",
                timeout_ms=args.page_timeout_ms,
                label="inspection-event",
                predicate=lambda event: event.get("payload", {}).get("ok") == "true",
            )

            cookie_set = client.request(
                "browser.cookie.set",
                browser_tab_id=main_context_id,
                page_id=main_page_id,
                label="browser.cookie.set.session",
                payload={"name": "session_token", "value": "alpha"},
            )
            cookie_get = client.request(
                "browser.cookie.get",
                browser_tab_id=main_context_id,
                page_id=main_page_id,
                label="browser.cookie.get.after-set",
            )
            cookie_delete = client.request(
                "browser.cookie.delete",
                browser_tab_id=main_context_id,
                page_id=main_page_id,
                label="browser.cookie.delete.session",
                payload={"name": "session_token"},
            )
            cookie_get_after_delete = client.request(
                "browser.cookie.get",
                browser_tab_id=main_context_id,
                page_id=main_page_id,
                label="browser.cookie.get.after-delete",
            )
            cookie_set_clear = client.request(
                "browser.cookie.set",
                browser_tab_id=main_context_id,
                page_id=main_page_id,
                label="browser.cookie.set.clear-target",
                payload={"name": "clear_me", "value": "beta"},
            )
            cookie_clear = client.request(
                "browser.cookie.clear",
                browser_tab_id=main_context_id,
                page_id=main_page_id,
                label="browser.cookie.clear.all",
            )
            cookie_get_after_clear = client.request(
                "browser.cookie.get",
                browser_tab_id=main_context_id,
                page_id=main_page_id,
                label="browser.cookie.get.after-clear",
            )

            dialog_schedule = client.request(
                "browser.dom.eval",
                browser_tab_id=main_context_id,
                page_id=main_page_id,
                label="browser.dom.eval.schedule-alert",
                payload={"script": "window.__ghxScheduleAlert(); 'scheduled'"},
            )
            dialog_requested = wait_for_event(
                client,
                browser_tab_id=main_context_id,
                subscription_id=subscription_id,
                kind="javaScriptDialog",
                timeout_ms=args.page_timeout_ms,
                label="dialog-requested",
                predicate=lambda event: event.get("payload", {}).get("phase") == "requested"
                and event.get("payload", {}).get("dialogType") == "alert",
            )
            dialog_request_id = str(dialog_requested["event"]["payload"]["requestID"])
            dialog_resolve = client.request(
                "browser.prompt.resolveDialog",
                browser_tab_id=main_context_id,
                page_id=main_page_id,
                label="browser.prompt.resolveDialog.alert",
                payload={"requestID": dialog_request_id, "accepted": "true"},
            )
            dialog_resolved = wait_for_event(
                client,
                browser_tab_id=main_context_id,
                subscription_id=subscription_id,
                kind="javaScriptDialog",
                timeout_ms=args.page_timeout_ms,
                label="dialog-resolved",
                predicate=lambda event: event.get("payload", {}).get("phase") == "resolved"
                and event.get("payload", {}).get("requestID") == dialog_request_id,
            )
            dialog_state = client.request(
                "browser.dom.eval",
                browser_tab_id=main_context_id,
                page_id=main_page_id,
                label="browser.dom.eval.dialog-state",
                payload={"script": "JSON.stringify(window.__ghxHarness)"},
            )

            permission_state_before = client.request(
                "browser.dom.eval",
                browser_tab_id=main_context_id,
                page_id=main_page_id,
                label="browser.dom.eval.permission-before",
                payload={"script": "JSON.stringify(window.__ghxHarness)"},
            )
            permission_click = client.request(
                "browser.dom.click",
                browser_tab_id=main_context_id,
                page_id=main_page_id,
                label="browser.dom.click.request-notification",
                payload={"selector": "#request-notification", "clickMode": "trusted"},
            )
            permission_requested = wait_for_event(
                client,
                browser_tab_id=main_context_id,
                subscription_id=subscription_id,
                kind="permissionRequest",
                timeout_ms=args.page_timeout_ms,
                label="permission-requested",
                predicate=lambda event: event.get("payload", {}).get("phase") == "requested",
            )
            permission_request_id = str(permission_requested["event"]["payload"]["requestID"])
            permission_resolve = client.request(
                "browser.prompt.resolvePermission",
                browser_tab_id=main_context_id,
                page_id=main_page_id,
                label="browser.prompt.resolvePermission.allow",
                payload={"requestID": permission_request_id, "result": "allow"},
            )
            permission_resolved = wait_for_event(
                client,
                browser_tab_id=main_context_id,
                subscription_id=subscription_id,
                kind="permissionRequest",
                timeout_ms=args.page_timeout_ms,
                label="permission-resolved",
                predicate=lambda event: event.get("payload", {}).get("phase") == "resolved"
                and event.get("payload", {}).get("requestID") == permission_request_id,
            )
            permission_responsive = wait_for_browser_control_responsive(
                client,
                browser_context_id=main_context_id,
                timeout_ms=args.page_timeout_ms,
                label="permission-responsive",
            )
            permission_state_after = wait_until(
                "notification grant visible in page state",
                lambda: (
                    response
                    if isinstance(response := client.request(
                        "browser.dom.eval",
                        browser_tab_id=main_context_id,
                        page_id=main_page_id,
                        label="browser.dom.eval.permission-after",
                        payload={"script": "JSON.stringify(window.__ghxHarness)"},
                    ).get("result"), str)
                    and json.loads(response).get("notificationResult") == "granted"
                    else None
                ),
                timeout_ms=args.page_timeout_ms,
            )

            auth_load = client.request(
                "browser.page.load",
                browser_context_id=main_context_id,
                page_id=main_page_id,
                label="browser.page.load.auth",
                payload={"url": auth_server["protected_url"]},
            )
            auth_requested = wait_for_event(
                client,
                browser_tab_id=main_context_id,
                subscription_id=subscription_id,
                kind="authenticationRequest",
                timeout_ms=args.page_timeout_ms,
                label="auth-requested",
                predicate=lambda event: event.get("payload", {}).get("phase") == "requested",
            )
            auth_request_id = str(auth_requested["event"]["payload"]["requestID"])
            auth_resolve = client.request(
                "browser.prompt.resolveAuth",
                browser_tab_id=main_context_id,
                page_id=main_page_id,
                label="browser.prompt.resolveAuth",
                payload={
                    "requestID": auth_request_id,
                    "accepted": "true",
                    "username": auth_server["username"],
                    "password": auth_server["password"],
                },
            )
            auth_resolved = wait_for_event(
                client,
                browser_tab_id=main_context_id,
                subscription_id=subscription_id,
                kind="authenticationRequest",
                timeout_ms=args.page_timeout_ms,
                label="auth-resolved",
                predicate=lambda event: event.get("payload", {}).get("phase") == "resolved"
                and event.get("payload", {}).get("requestID") == auth_request_id,
            )
            auth_responsive = wait_for_browser_control_responsive(
                client,
                browser_context_id=main_context_id,
                timeout_ms=args.page_timeout_ms,
                label="auth-responsive",
            )
            auth_ready = wait_for_selector(
                client,
                browser_tab_id=main_context_id,
                page_id=main_page_id,
                selector="#auth-ok",
                timeout_ms=args.page_timeout_ms,
                label="auth-ready",
            )

            cert_load = client.request(
                "browser.page.load",
                browser_context_id=main_context_id,
                page_id=main_page_id,
                label="browser.page.load.certificate",
                payload={"url": cert_server["index_url"]},
            )
            cert_requested = wait_for_event(
                client,
                browser_tab_id=main_context_id,
                subscription_id=subscription_id,
                kind="certificateWarning",
                timeout_ms=args.page_timeout_ms,
                label="certificate-requested",
                predicate=lambda event: event.get("payload", {}).get("phase") == "requested",
            )
            cert_request_id = str(cert_requested["event"]["payload"]["requestID"])
            cert_resolve = client.request(
                "browser.prompt.resolveCertificate",
                browser_tab_id=main_context_id,
                page_id=main_page_id,
                label="browser.prompt.resolveCertificate",
                payload={"requestID": cert_request_id, "accepted": "true"},
            )
            cert_resolved = wait_for_event(
                client,
                browser_tab_id=main_context_id,
                subscription_id=subscription_id,
                kind="certificateWarning",
                timeout_ms=args.page_timeout_ms,
                label="certificate-resolved",
                predicate=lambda event: event.get("payload", {}).get("phase") == "resolved"
                and event.get("payload", {}).get("requestID") == cert_request_id,
            )
            cert_responsive = wait_for_browser_control_responsive(
                client,
                browser_context_id=main_context_id,
                timeout_ms=args.page_timeout_ms,
                label="certificate-responsive",
            )
            cert_ready = wait_for_selector(
                client,
                browser_tab_id=main_context_id,
                page_id=main_page_id,
                selector="#cert-ok",
                timeout_ms=args.page_timeout_ms,
                label="certificate-ready",
            )

            load_index_again = client.request(
                "browser.page.load",
                browser_context_id=main_context_id,
                page_id=main_page_id,
                label="browser.page.load.index-after-prompts",
                payload={"url": fixture_server["index_url"]},
            )
            wait_for_selector(
                client,
                browser_tab_id=main_context_id,
                page_id=main_page_id,
                selector="#download-link",
                timeout_ms=args.page_timeout_ms,
                label="download-page-ready",
            )
            download_click = client.request(
                "browser.dom.click",
                browser_tab_id=main_context_id,
                page_id=main_page_id,
                label="browser.dom.click.download-link",
                payload={"selector": "#download-link", "clickMode": "trusted"},
            )
            download_started = wait_for_event(
                client,
                browser_tab_id=main_context_id,
                subscription_id=subscription_id,
                kind="download",
                timeout_ms=args.page_timeout_ms,
                label="download-started",
                predicate=lambda event: event.get("payload", {}).get("phase") == "started"
                and event.get("payload", {}).get("url") == fixture_server["download_url"],
            )
            download_id = str(download_started["event"]["payload"]["downloadID"])
            download_cancel = client.request(
                "browser.download.cancel",
                browser_tab_id=main_context_id,
                page_id=main_page_id,
                label="browser.download.cancel",
                payload={"downloadID": download_id},
            )
            download_canceled = wait_for_event(
                client,
                browser_tab_id=main_context_id,
                subscription_id=subscription_id,
                kind="download",
                timeout_ms=args.page_timeout_ms,
                label="download-canceled",
                predicate=lambda event: event.get("payload", {}).get("downloadID") == download_id
                and event.get("payload", {}).get("phase") in {"canceled", "interrupted"},
            )

            compatibility_expected_commands = {
                "browser.listTabs",
                "browser.newTab",
                "browser.listContexts",
                "browser.getContext",
                "browser.newContext",
                "browser.closeContext",
                "browser.activateContext",
                "browser.listPages",
                "browser.newPageInContext",
                "browser.getActivePage",
                "browser.page.get_active",
                "browser.activatePage",
                "browser.closePage",
                "browser.listFrames",
                "browser.getDebugStatus",
                "browser.loadURL",
                "browser.page.navigate",
                "browser.goBack",
                "browser.goForward",
                "browser.reload",
                "browser.getCookies",
                "browser.setCookie",
                "browser.deleteCookie",
                "browser.clearCookies",
                "browser.evaluateJavaScript",
                "browser.script.eval",
                "browser.query",
                "browser.click",
                "browser.typeText",
                "browser.waitForSelector",
                "browser.dom.wait",
                "browser.getText",
                "browser.getAttributes",
                "browser.getBoundingBox",
                "browser.getDOMSnapshot",
                "browser.runDOMBatch",
                "browser.subscribeEvents",
                "browser.drainEvents",
                "browser.unsubscribeEvents",
                "browser.resolveDialog",
                "browser.resolvePermission",
                "browser.resolveAuth",
                "browser.resolveCertificate",
                "browser.cancelDownload",
                "browser.tab.create",
            }
            compat_index_url = fixture_server["index_url"].replace("127.0.0.1", "localhost")
            compat_second_url = fixture_server["second_url"].replace("127.0.0.1", "localhost")
            compat_download_url = fixture_server["download_url"].replace("127.0.0.1", "localhost")

            compat_main_context = client.request(
                "browser.newContext",
                label="compat.browser.newContext",
                payload={"url": compat_index_url},
            )["result"]
            compat_main_context_id = str(compat_main_context["id"])
            compat_main_context_summary = wait_for_context_summary(
                client,
                browser_context_id=compat_main_context_id,
                timeout_ms=args.page_timeout_ms,
                label="compat-main-context",
            )
            compat_main_page_id = str(compat_main_context_summary["activePageID"])
            wait_for_selector(
                client,
                browser_tab_id=compat_main_context_id,
                page_id=compat_main_page_id,
                selector="#ready-marker",
                timeout_ms=args.page_timeout_ms,
                label="compat-main-ready",
            )
            record_compatibility_result(
                artifact,
                command="browser.newContext",
                response={"status": "ok", "request_id": compat_main_context.get("requestID")},
                evidence={
                    "context_id": compat_main_context_id,
                    "page_id": compat_main_page_id,
                },
            )

            compat_new_tab = client.request(
                "browser.newTab",
                label="compat.browser.newTab",
                payload={"url": compat_second_url},
            )["result"]
            compat_new_tab_id = str(compat_new_tab["id"])
            compat_new_tab_summary = wait_for_context_summary(
                client,
                browser_context_id=compat_new_tab_id,
                timeout_ms=args.page_timeout_ms,
                label="compat-new-tab-context",
            )
            compat_new_tab_page_id = str(compat_new_tab_summary["activePageID"])
            wait_for_selector(
                client,
                browser_tab_id=compat_new_tab_id,
                page_id=compat_new_tab_page_id,
                selector="#second-marker",
                timeout_ms=args.page_timeout_ms,
                label="compat-new-tab-ready",
            )
            record_compatibility_result(
                artifact,
                command="browser.newTab",
                response={"status": "ok", "request_id": compat_new_tab.get("requestID")},
                evidence={
                    "context_id": compat_new_tab_id,
                    "page_id": compat_new_tab_page_id,
                },
            )

            compat_tab_create_response = client.request(
                "browser.tab.create",
                label="compat.browser.tab.create",
                payload={"url": compat_second_url},
            )
            compat_tab_create_id = str(compat_tab_create_response["result"]["id"])
            compat_tab_create_summary = wait_for_context_summary(
                client,
                browser_context_id=compat_tab_create_id,
                timeout_ms=args.page_timeout_ms,
                label="compat-tab-create-context",
            )
            wait_for_selector(
                client,
                browser_tab_id=compat_tab_create_id,
                page_id=str(compat_tab_create_summary["activePageID"]),
                selector="#second-marker",
                timeout_ms=args.page_timeout_ms,
                label="compat-tab-create-ready",
            )
            record_compatibility_result(
                artifact,
                command="browser.tab.create",
                response=compat_tab_create_response,
                evidence={"context_id": compat_tab_create_id},
            )

            compat_list_tabs = client.request("browser.listTabs", label="compat.browser.listTabs")
            compat_tab_ids = {str(tab.get("id")) for tab in (compat_list_tabs.get("result") or [])}
            require(
                {compat_main_context_id, compat_new_tab_id, compat_tab_create_id}.issubset(compat_tab_ids),
                "browser.listTabs did not include all compatibility contexts",
            )
            record_compatibility_result(
                artifact,
                command="browser.listTabs",
                response=compat_list_tabs,
                evidence={"tab_ids": sorted(compat_tab_ids)},
            )

            compat_list_contexts = client.request("browser.listContexts", label="compat.browser.listContexts")
            compat_context_ids = {str(context.get("id")) for context in (compat_list_contexts.get("result") or [])}
            require(
                compat_main_context_id in compat_context_ids,
                "browser.listContexts omitted the compatibility main context",
            )
            record_compatibility_result(
                artifact,
                command="browser.listContexts",
                response=compat_list_contexts,
                evidence={"context_ids": sorted(compat_context_ids)},
            )

            compat_get_context = client.request(
                "browser.getContext",
                label="compat.browser.getContext",
                browser_context_id=compat_main_context_id,
            )
            require(str(compat_get_context["result"]["id"]) == compat_main_context_id, "browser.getContext returned the wrong context")
            record_compatibility_result(
                artifact,
                command="browser.getContext",
                response=compat_get_context,
                evidence={"context_id": compat_main_context_id},
            )

            compat_activate_context = client.request(
                "browser.activateContext",
                label="compat.browser.activateContext",
                browser_context_id=compat_main_context_id,
            )
            compat_active_context = wait_until(
                "compat main context frontmost",
                lambda: (
                    response.get("result")
                    if (response := client.request(
                        "browser.context.get",
                        label="compat.browser.context.get.frontmost",
                        browser_context_id=compat_main_context_id,
                    )).get("result", {}).get("isFrontmost") is True
                    else None
                ),
                timeout_ms=args.page_timeout_ms,
            )
            record_compatibility_result(
                artifact,
                command="browser.activateContext",
                response=compat_activate_context,
                evidence={"is_frontmost": compat_active_context["isFrontmost"]},
            )

            compat_list_pages = client.request(
                "browser.listPages",
                label="compat.browser.listPages",
                browser_context_id=compat_main_context_id,
            )
            require(
                any(str(page.get("id")) == compat_main_page_id for page in compat_list_pages["result"]),
                "browser.listPages omitted the compatibility main page",
            )
            record_compatibility_result(
                artifact,
                command="browser.listPages",
                response=compat_list_pages,
                evidence={"page_ids": [str(page.get("id")) for page in compat_list_pages["result"]]},
            )

            compat_get_active_page = client.request(
                "browser.getActivePage",
                label="compat.browser.getActivePage",
                browser_context_id=compat_main_context_id,
            )
            require(
                str(compat_get_active_page["result"]["id"]) == compat_main_page_id,
                "browser.getActivePage returned the wrong page",
            )
            record_compatibility_result(
                artifact,
                command="browser.getActivePage",
                response=compat_get_active_page,
                evidence={"page_id": compat_main_page_id},
            )

            compat_get_active_page_protocol = client.request(
                "browser.page.get_active",
                label="compat.browser.page.get_active",
                browser_context_id=compat_main_context_id,
            )
            require(
                str(compat_get_active_page_protocol["result"]["id"]) == compat_main_page_id,
                "browser.page.get_active returned the wrong page",
            )
            record_compatibility_result(
                artifact,
                command="browser.page.get_active",
                response=compat_get_active_page_protocol,
                evidence={"page_id": compat_main_page_id},
            )

            compat_new_page = client.request(
                "browser.newPageInContext",
                label="compat.browser.newPageInContext",
                browser_context_id=compat_main_context_id,
                payload={"url": fixture_server["second_url"]},
            )["result"]
            compat_extra_page_id = str(compat_new_page["id"])
            wait_for_selector(
                client,
                browser_tab_id=compat_main_context_id,
                page_id=compat_extra_page_id,
                selector="#second-marker",
                timeout_ms=args.page_timeout_ms,
                label="compat-extra-page-ready",
            )
            record_compatibility_result(
                artifact,
                command="browser.newPageInContext",
                response={"status": "ok", "request_id": compat_new_page.get("requestID")},
                evidence={"page_id": compat_extra_page_id},
            )

            compat_activate_page = client.request(
                "browser.activatePage",
                label="compat.browser.activatePage",
                browser_context_id=compat_main_context_id,
                page_id=compat_main_page_id,
            )
            wait_for_active_page(
                client,
                browser_context_id=compat_main_context_id,
                expected_page_id=compat_main_page_id,
                timeout_ms=args.page_timeout_ms,
                label="compat-active-main-page",
            )
            record_compatibility_result(
                artifact,
                command="browser.activatePage",
                response=compat_activate_page,
                evidence={"page_id": compat_main_page_id},
            )

            compat_load_url = client.request(
                "browser.loadURL",
                label="compat.browser.loadURL",
                browser_context_id=compat_main_context_id,
                page_id=compat_main_page_id,
                payload={"url": compat_second_url},
            )
            wait_for_selector(
                client,
                browser_tab_id=compat_main_context_id,
                page_id=compat_main_page_id,
                selector="#second-marker",
                timeout_ms=args.page_timeout_ms,
                label="compat-load-second",
            )
            record_compatibility_result(
                artifact,
                command="browser.loadURL",
                response=compat_load_url,
                evidence={"url": compat_second_url},
            )

            compat_page_navigate = client.request(
                "browser.page.navigate",
                label="compat.browser.page.navigate",
                browser_context_id=compat_main_context_id,
                page_id=compat_main_page_id,
                payload={"url": compat_index_url},
            )
            wait_for_selector(
                client,
                browser_tab_id=compat_main_context_id,
                page_id=compat_main_page_id,
                selector="#ready-marker",
                timeout_ms=args.page_timeout_ms,
                label="compat-navigate-index",
            )
            record_compatibility_result(
                artifact,
                command="browser.page.navigate",
                response=compat_page_navigate,
                evidence={"url": compat_index_url},
            )

            compat_go_back = client.request(
                "browser.goBack",
                label="compat.browser.goBack",
                browser_context_id=compat_main_context_id,
                page_id=compat_main_page_id,
            )
            wait_for_selector(
                client,
                browser_tab_id=compat_main_context_id,
                page_id=compat_main_page_id,
                selector="#second-marker",
                timeout_ms=args.page_timeout_ms,
                label="compat-back-second",
            )
            record_compatibility_result(
                artifact,
                command="browser.goBack",
                response=compat_go_back,
                evidence={"operation": compat_go_back["result"]["operation"]},
            )

            compat_go_forward = client.request(
                "browser.goForward",
                label="compat.browser.goForward",
                browser_context_id=compat_main_context_id,
                page_id=compat_main_page_id,
            )
            wait_for_selector(
                client,
                browser_tab_id=compat_main_context_id,
                page_id=compat_main_page_id,
                selector="#ready-marker",
                timeout_ms=args.page_timeout_ms,
                label="compat-forward-index",
            )
            record_compatibility_result(
                artifact,
                command="browser.goForward",
                response=compat_go_forward,
                evidence={"operation": compat_go_forward["result"]["operation"]},
            )

            compat_reload = client.request(
                "browser.reload",
                label="compat.browser.reload",
                browser_context_id=compat_main_context_id,
                page_id=compat_main_page_id,
            )
            wait_for_selector(
                client,
                browser_tab_id=compat_main_context_id,
                page_id=compat_main_page_id,
                selector="#ready-marker",
                timeout_ms=args.page_timeout_ms,
                label="compat-reload-index",
            )
            record_compatibility_result(
                artifact,
                command="browser.reload",
                response=compat_reload,
                evidence={"operation": compat_reload["result"]["operation"]},
            )

            compat_list_frames = client.request(
                "browser.listFrames",
                label="compat.browser.listFrames",
                browser_context_id=compat_main_context_id,
                page_id=compat_main_page_id,
            )
            require(any(bool(frame.get("isMainFrame")) for frame in compat_list_frames["result"]), "browser.listFrames omitted the main frame")
            record_compatibility_result(
                artifact,
                command="browser.listFrames",
                response=compat_list_frames,
                evidence={"frame_count": len(compat_list_frames["result"])},
            )

            compat_debug_status = client.request(
                "browser.getDebugStatus",
                label="compat.browser.getDebugStatus",
            )
            require(compat_debug_status["result"]["runtimeAvailable"] is True, "browser.getDebugStatus reported runtime unavailable")
            record_compatibility_result(
                artifact,
                command="browser.getDebugStatus",
                response=compat_debug_status,
                evidence=compat_debug_status["result"],
            )

            compat_wait_for_selector = client.request(
                "browser.waitForSelector",
                label="compat.browser.waitForSelector",
                browser_tab_id=compat_main_context_id,
                page_id=compat_main_page_id,
                payload={"selector": "#ready-marker", "state": "present", "timeoutMS": "5000"},
            )
            record_compatibility_result(
                artifact,
                command="browser.waitForSelector",
                response=compat_wait_for_selector,
                evidence={"selector": "#ready-marker"},
            )

            compat_dom_wait = client.request(
                "browser.dom.wait",
                label="compat.browser.dom.wait",
                browser_tab_id=compat_main_context_id,
                page_id=compat_main_page_id,
                payload={"selector": "#click-target", "state": "present", "timeoutMS": "5000"},
            )
            record_compatibility_result(
                artifact,
                command="browser.dom.wait",
                response=compat_dom_wait,
                evidence={"selector": "#click-target"},
            )

            compat_query = client.request(
                "browser.query",
                label="compat.browser.query",
                browser_tab_id=compat_main_context_id,
                page_id=compat_main_page_id,
                payload={"selector": "#click-target"},
            )
            require(compat_query["result"]["found"] is True, "browser.query did not find #click-target")
            record_compatibility_result(
                artifact,
                command="browser.query",
                response=compat_query,
                evidence={"selector": "#click-target"},
            )

            compat_click = client.request(
                "browser.click",
                label="compat.browser.click",
                browser_tab_id=compat_main_context_id,
                page_id=compat_main_page_id,
                payload={"selector": "#click-target", "clickMode": "trusted"},
            )
            require(compat_click["result"]["clicked"] is True, "browser.click did not click #click-target")
            record_compatibility_result(
                artifact,
                command="browser.click",
                response=compat_click,
                evidence={"selector": "#click-target"},
            )

            compat_type = client.request(
                "browser.typeText",
                label="compat.browser.typeText",
                browser_tab_id=compat_main_context_id,
                page_id=compat_main_page_id,
                payload={"selector": "#name-input", "text": "Compat Leon"},
            )
            require(compat_type["result"]["value"] == "Compat Leon", "browser.typeText did not set the expected value")
            record_compatibility_result(
                artifact,
                command="browser.typeText",
                response=compat_type,
                evidence={"selector": "#name-input", "value": compat_type["result"]["value"]},
            )

            compat_get_text = client.request(
                "browser.getText",
                label="compat.browser.getText",
                browser_tab_id=compat_main_context_id,
                page_id=compat_main_page_id,
                payload={"selector": "#status"},
            )
            require(compat_get_text["result"]["text"] == "clicked", "browser.getText did not observe clicked status")
            record_compatibility_result(
                artifact,
                command="browser.getText",
                response=compat_get_text,
                evidence={"text": compat_get_text["result"]["text"]},
            )

            compat_get_attributes = client.request(
                "browser.getAttributes",
                label="compat.browser.getAttributes",
                browser_tab_id=compat_main_context_id,
                page_id=compat_main_page_id,
                payload={"selector": "#click-target"},
            )
            require(
                compat_get_attributes["result"]["attributes"]["data-role"] == "action",
                "browser.getAttributes did not expose data-role=action",
            )
            record_compatibility_result(
                artifact,
                command="browser.getAttributes",
                response=compat_get_attributes,
                evidence={"attributes": compat_get_attributes["result"]["attributes"]},
            )

            compat_get_bounding_box = client.request(
                "browser.getBoundingBox",
                label="compat.browser.getBoundingBox",
                browser_tab_id=compat_main_context_id,
                page_id=compat_main_page_id,
                payload={"selector": "#click-target"},
            )
            require((compat_get_bounding_box["result"]["width"] or 0) > 0, "browser.getBoundingBox width was not positive")
            record_compatibility_result(
                artifact,
                command="browser.getBoundingBox",
                response=compat_get_bounding_box,
                evidence={"width": compat_get_bounding_box["result"]["width"]},
            )

            compat_dom_snapshot = client.request(
                "browser.getDOMSnapshot",
                label="compat.browser.getDOMSnapshot",
                browser_tab_id=compat_main_context_id,
                page_id=compat_main_page_id,
                payload={"selector": "body", "maxDepth": "2", "includeText": "true"},
            )
            require(compat_dom_snapshot["result"]["found"] is True, "browser.getDOMSnapshot did not return a snapshot")
            record_compatibility_result(
                artifact,
                command="browser.getDOMSnapshot",
                response=compat_dom_snapshot,
                evidence={"found": compat_dom_snapshot["result"]["found"]},
            )

            compat_batch_commands = [
                {"id": str(uuid.uuid4()), "command": "query", "selector": "#click-target"},
                {"id": str(uuid.uuid4()), "command": "getText", "selector": "#status"},
            ]
            compat_dom_batch = client.request(
                "browser.runDOMBatch",
                label="compat.browser.runDOMBatch",
                browser_tab_id=compat_main_context_id,
                page_id=compat_main_page_id,
                payload={"commandsJSON": json.dumps(compat_batch_commands)},
            )
            require(
                len(compat_dom_batch["result"]["results"]) == len(compat_batch_commands),
                "browser.runDOMBatch result count did not match",
            )
            record_compatibility_result(
                artifact,
                command="browser.runDOMBatch",
                response=compat_dom_batch,
                evidence={"result_count": len(compat_dom_batch["result"]["results"])},
            )

            compat_eval = client.request(
                "browser.evaluateJavaScript",
                label="compat.browser.evaluateJavaScript",
                browser_tab_id=compat_main_context_id,
                page_id=compat_main_page_id,
                payload={"script": "JSON.stringify(window.__ghxHarness)"},
            )
            require(json.loads(compat_eval["result"])["notificationSupported"] is True, "browser.evaluateJavaScript returned malformed state")
            record_compatibility_result(
                artifact,
                command="browser.evaluateJavaScript",
                response=compat_eval,
                evidence={"notification_supported": json.loads(compat_eval["result"])["notificationSupported"]},
            )

            compat_script_eval = client.request(
                "browser.script.eval",
                label="compat.browser.script.eval",
                browser_tab_id=compat_main_context_id,
                page_id=compat_main_page_id,
                payload={"script": "document.querySelector('#ready-marker').textContent"},
            )
            require(compat_script_eval["result"] == "control-browser-index", "browser.script.eval returned the wrong text")
            record_compatibility_result(
                artifact,
                command="browser.script.eval",
                response=compat_script_eval,
                evidence={"text": compat_script_eval["result"]},
            )

            compat_set_cookie = client.request(
                "browser.setCookie",
                label="compat.browser.setCookie",
                browser_tab_id=compat_main_context_id,
                page_id=compat_main_page_id,
                payload={"name": "compat_cookie", "value": "alpha"},
            )
            record_compatibility_result(
                artifact,
                command="browser.setCookie",
                response=compat_set_cookie,
                evidence={"cookie": "compat_cookie"},
            )

            compat_get_cookies = client.request(
                "browser.getCookies",
                label="compat.browser.getCookies",
                browser_tab_id=compat_main_context_id,
                page_id=compat_main_page_id,
            )
            compat_cookie_names_after_set = {entry["name"] for entry in compat_get_cookies["result"]["cookies"]}
            require("compat_cookie" in compat_cookie_names_after_set, "browser.getCookies did not surface compat_cookie")
            record_compatibility_result(
                artifact,
                command="browser.getCookies",
                response=compat_get_cookies,
                evidence={"cookie_names": sorted(compat_cookie_names_after_set)},
            )

            compat_delete_cookie = client.request(
                "browser.deleteCookie",
                label="compat.browser.deleteCookie",
                browser_tab_id=compat_main_context_id,
                page_id=compat_main_page_id,
                payload={"name": "compat_cookie"},
            )
            record_compatibility_result(
                artifact,
                command="browser.deleteCookie",
                response=compat_delete_cookie,
                evidence={"cookie": "compat_cookie"},
            )

            client.request(
                "browser.setCookie",
                label="compat.browser.setCookie.clear-me",
                browser_tab_id=compat_main_context_id,
                page_id=compat_main_page_id,
                payload={"name": "compat_clear", "value": "beta"},
            )
            compat_clear_cookies = client.request(
                "browser.clearCookies",
                label="compat.browser.clearCookies",
                browser_tab_id=compat_main_context_id,
                page_id=compat_main_page_id,
            )
            compat_cookies_after_clear = client.request(
                "browser.cookie.get",
                label="compat.browser.clearCookies.verify",
                browser_tab_id=compat_main_context_id,
                page_id=compat_main_page_id,
            )
            require(
                "compat_clear" not in {entry["name"] for entry in compat_cookies_after_clear["result"]["cookies"]},
                "browser.clearCookies did not remove compat_clear",
            )
            record_compatibility_result(
                artifact,
                command="browser.clearCookies",
                response=compat_clear_cookies,
                evidence={"cookie_count_after_clear": len(compat_cookies_after_clear["result"]["cookies"])},
            )

            compat_subscribe_events = client.request(
                "browser.subscribeEvents",
                label="compat.browser.subscribeEvents",
                browser_tab_id=compat_main_context_id,
                payload={
                    "eventKinds": "navigationStateChanged,pageInspectionSnapshot,download,javaScriptDialog,permissionRequest,authenticationRequest,certificateWarning"
                },
            )
            compat_subscription_id = str(compat_subscribe_events["result"]["subscriptionID"])
            record_compatibility_result(
                artifact,
                command="browser.subscribeEvents",
                response=compat_subscribe_events,
                evidence={"subscription_id": compat_subscription_id},
            )

            compat_event_buffer: list[dict[str, Any]] = []
            compat_drain_recorded = False

            def wait_for_compat_event(
                kind: str,
                *,
                label: str,
                predicate: Callable[[dict[str, Any]], bool] | None = None,
            ) -> dict[str, Any]:
                nonlocal compat_drain_recorded

                def inner() -> dict[str, Any] | None:
                    for index, event in enumerate(compat_event_buffer):
                        if event.get("kind") != kind:
                            continue
                        if predicate is not None and not predicate(event):
                            continue
                        return compat_event_buffer.pop(index)

                    try:
                        response = client.request(
                            "browser.drainEvents",
                            label=f"{label}.drain",
                            browser_tab_id=compat_main_context_id,
                            payload={"subscriptionID": compat_subscription_id, "limit": "128"},
                            timeout=min(2.0, client.timeout),
                        )
                    except TimeoutError:
                        return None
                    except socket.timeout:
                        return None
                    events = response.get("result", {}).get("events") or []
                    compat_event_buffer.extend(events)
                    if not compat_drain_recorded and events:
                        record_compatibility_result(
                            artifact,
                            command="browser.drainEvents",
                            response=response,
                            evidence={
                                "subscription_id": compat_subscription_id,
                                "drained_event_count": len(events),
                                "first_kind": events[0].get("kind"),
                            },
                        )
                        compat_drain_recorded = True

                    for index, event in enumerate(compat_event_buffer):
                        if event.get("kind") != kind:
                            continue
                        if predicate is not None and not predicate(event):
                            continue
                        return compat_event_buffer.pop(index)
                    return None

                return wait_until(f"compat event {kind}", inner, timeout_ms=args.page_timeout_ms)

            compat_page_navigate_events = client.request(
                "browser.page.navigate",
                label="compat.browser.page.navigate.events",
                browser_context_id=compat_main_context_id,
                page_id=compat_main_page_id,
                payload={"url": compat_second_url},
            )
            wait_for_selector(
                client,
                browser_tab_id=compat_main_context_id,
                page_id=compat_main_page_id,
                selector="#second-marker",
                timeout_ms=args.page_timeout_ms,
                label="compat-events-second",
            )
            compat_nav_event = wait_for_compat_event(
                "navigationStateChanged",
                label="compat-nav-event",
                predicate=lambda event: event.get("payload", {}).get("url") == compat_second_url
                and event.get("payload", {}).get("isLoading") == "false",
            )
            wait_for_compat_event(
                "pageInspectionSnapshot",
                label="compat-inspection-event",
                predicate=lambda event: event.get("payload", {}).get("ok") == "true",
            )
            client.request(
                "browser.page.load",
                label="compat.browser.page.load.index-before-dialog",
                browser_context_id=compat_main_context_id,
                page_id=compat_main_page_id,
                payload={"url": compat_index_url},
            )
            wait_for_selector(
                client,
                browser_tab_id=compat_main_context_id,
                page_id=compat_main_page_id,
                selector="#ready-marker",
                timeout_ms=args.page_timeout_ms,
                label="compat-index-before-dialog",
            )

            compat_dialog_schedule = client.request(
                "browser.script.eval",
                label="compat.browser.script.eval.schedule-alert",
                browser_tab_id=compat_main_context_id,
                page_id=compat_main_page_id,
                payload={"script": "window.__ghxScheduleAlert(); 'scheduled'"},
            )
            compat_dialog_requested = wait_for_compat_event(
                "javaScriptDialog",
                label="compat-dialog-requested",
                predicate=lambda event: event.get("payload", {}).get("phase") == "requested"
                and event.get("payload", {}).get("dialogType") == "alert",
            )
            compat_dialog_request_id = str(compat_dialog_requested["payload"]["requestID"])
            compat_resolve_dialog = client.request(
                "browser.resolveDialog",
                label="compat.browser.resolveDialog",
                browser_tab_id=compat_main_context_id,
                page_id=compat_main_page_id,
                payload={"requestID": compat_dialog_request_id, "accepted": "true"},
            )
            wait_for_compat_event(
                "javaScriptDialog",
                label="compat-dialog-resolved",
                predicate=lambda event: event.get("payload", {}).get("phase") == "resolved"
                and event.get("payload", {}).get("requestID") == compat_dialog_request_id,
            )
            compat_dialog_state = client.request(
                "browser.evaluateJavaScript",
                label="compat.browser.evaluateJavaScript.dialog-state",
                browser_tab_id=compat_main_context_id,
                page_id=compat_main_page_id,
                payload={"script": "JSON.stringify(window.__ghxHarness)"},
            )
            require(json.loads(compat_dialog_state["result"])["alertDone"] is True, "browser.resolveDialog did not update alert state")
            record_compatibility_result(
                artifact,
                command="browser.resolveDialog",
                response=compat_resolve_dialog,
                evidence={"request_id": compat_dialog_request_id},
            )

            compat_permission_click = client.request(
                "browser.click",
                label="compat.browser.click.permission",
                browser_tab_id=compat_main_context_id,
                page_id=compat_main_page_id,
                payload={"selector": "#request-notification", "clickMode": "trusted"},
            )
            compat_permission_requested = wait_for_compat_event(
                "permissionRequest",
                label="compat-permission-requested",
                predicate=lambda event: event.get("payload", {}).get("phase") == "requested",
            )
            compat_permission_request_id = str(compat_permission_requested["payload"]["requestID"])
            compat_resolve_permission = client.request(
                "browser.resolvePermission",
                label="compat.browser.resolvePermission",
                browser_tab_id=compat_main_context_id,
                page_id=compat_main_page_id,
                payload={"requestID": compat_permission_request_id, "result": "allow"},
            )
            wait_for_compat_event(
                "permissionRequest",
                label="compat-permission-resolved",
                predicate=lambda event: event.get("payload", {}).get("phase") == "resolved"
                and event.get("payload", {}).get("requestID") == compat_permission_request_id,
            )
            compat_permission_state = wait_until(
                "compat permission state granted",
                lambda: (
                    response
                    if isinstance(response := client.request(
                        "browser.evaluateJavaScript",
                        label="compat.browser.evaluateJavaScript.permission-state",
                        browser_tab_id=compat_main_context_id,
                        page_id=compat_main_page_id,
                        payload={"script": "JSON.stringify(window.__ghxHarness)"},
                    ).get("result"), str)
                    and json.loads(response).get("notificationResult") == "granted"
                    else None
                ),
                timeout_ms=args.page_timeout_ms,
            )
            record_compatibility_result(
                artifact,
                command="browser.resolvePermission",
                response=compat_resolve_permission,
                evidence={"request_id": compat_permission_request_id, "state": json.loads(compat_permission_state)["notificationResult"]},
            )

            compat_auth_load = client.request(
                "browser.loadURL",
                label="compat.browser.loadURL.auth",
                browser_context_id=compat_main_context_id,
                page_id=compat_main_page_id,
                payload={"url": auth_server["protected_url"]},
            )
            compat_auth_requested = wait_for_compat_event(
                "authenticationRequest",
                label="compat-auth-requested",
                predicate=lambda event: event.get("payload", {}).get("phase") == "requested",
            )
            compat_auth_request_id = str(compat_auth_requested["payload"]["requestID"])
            compat_resolve_auth = client.request(
                "browser.resolveAuth",
                label="compat.browser.resolveAuth",
                browser_tab_id=compat_main_context_id,
                page_id=compat_main_page_id,
                payload={
                    "requestID": compat_auth_request_id,
                    "accepted": "true",
                    "username": auth_server["username"],
                    "password": auth_server["password"],
                },
            )
            wait_for_compat_event(
                "authenticationRequest",
                label="compat-auth-resolved",
                predicate=lambda event: event.get("payload", {}).get("phase") == "resolved"
                and event.get("payload", {}).get("requestID") == compat_auth_request_id,
            )
            wait_for_selector(
                client,
                browser_tab_id=compat_main_context_id,
                page_id=compat_main_page_id,
                selector="#auth-ok",
                timeout_ms=args.page_timeout_ms,
                label="compat-auth-ready",
            )
            record_compatibility_result(
                artifact,
                command="browser.resolveAuth",
                response=compat_resolve_auth,
                evidence={"request_id": compat_auth_request_id},
            )

            compat_cert_load = client.request(
                "browser.page.navigate",
                label="compat.browser.page.navigate.certificate",
                browser_context_id=compat_main_context_id,
                page_id=compat_main_page_id,
                payload={"url": compat_cert_server["index_url"]},
            )
            compat_cert_requested = wait_for_compat_event(
                "certificateWarning",
                label="compat-cert-requested",
                predicate=lambda event: event.get("payload", {}).get("phase") == "requested",
            )
            compat_cert_request_id = str(compat_cert_requested["payload"]["requestID"])
            compat_resolve_cert = client.request(
                "browser.resolveCertificate",
                label="compat.browser.resolveCertificate",
                browser_tab_id=compat_main_context_id,
                page_id=compat_main_page_id,
                payload={"requestID": compat_cert_request_id, "accepted": "true"},
            )
            wait_for_compat_event(
                "certificateWarning",
                label="compat-cert-resolved",
                predicate=lambda event: event.get("payload", {}).get("phase") == "resolved"
                and event.get("payload", {}).get("requestID") == compat_cert_request_id,
            )
            wait_for_selector(
                client,
                browser_tab_id=compat_main_context_id,
                page_id=compat_main_page_id,
                selector="#cert-ok",
                timeout_ms=args.page_timeout_ms,
                label="compat-cert-ready",
            )
            record_compatibility_result(
                artifact,
                command="browser.resolveCertificate",
                response=compat_resolve_cert,
                evidence={"request_id": compat_cert_request_id},
            )

            compat_back_to_index = client.request(
                "browser.loadURL",
                label="compat.browser.loadURL.index-after-prompts",
                browser_context_id=compat_main_context_id,
                page_id=compat_main_page_id,
                payload={"url": compat_index_url},
            )
            wait_for_selector(
                client,
                browser_tab_id=compat_main_context_id,
                page_id=compat_main_page_id,
                selector="#download-link",
                timeout_ms=args.page_timeout_ms,
                label="compat-download-page-ready",
            )
            compat_download_click = client.request(
                "browser.click",
                label="compat.browser.click.download-link",
                browser_tab_id=compat_main_context_id,
                page_id=compat_main_page_id,
                payload={"selector": "#download-link", "clickMode": "trusted"},
            )
            compat_download_started = wait_for_compat_event(
                "download",
                label="compat-download-started",
                predicate=lambda event: event.get("payload", {}).get("phase") == "started"
                and event.get("payload", {}).get("url") == compat_download_url,
            )
            compat_download_id = str(compat_download_started["payload"]["downloadID"])
            compat_cancel_download = client.request(
                "browser.cancelDownload",
                label="compat.browser.cancelDownload",
                browser_tab_id=compat_main_context_id,
                page_id=compat_main_page_id,
                payload={"downloadID": compat_download_id},
            )
            wait_for_compat_event(
                "download",
                label="compat-download-canceled",
                predicate=lambda event: event.get("payload", {}).get("downloadID") == compat_download_id
                and event.get("payload", {}).get("phase") in {"canceled", "interrupted"},
            )
            record_compatibility_result(
                artifact,
                command="browser.cancelDownload",
                response=compat_cancel_download,
                evidence={"download_id": compat_download_id},
            )

            compat_unsubscribe = client.request(
                "browser.unsubscribeEvents",
                label="compat.browser.unsubscribeEvents",
                browser_tab_id=compat_main_context_id,
                payload={"subscriptionID": compat_subscription_id},
            )
            if not any(
                entry["command"] == "browser.drainEvents"
                for entry in artifact.get("compatibility_matrix", [])
            ):
                for request_label in artifact.get("request_order", []):
                    if not request_label.startswith("compat-") or ".drain" not in request_label:
                        continue
                    request_record = artifact.get("requests", {}).get(request_label) or {}
                    drain_response = request_record.get("response") or {}
                    drain_events = drain_response.get("result", {}).get("events") or []
                    if not drain_events:
                        continue
                    record_compatibility_result(
                        artifact,
                        command="browser.drainEvents",
                        response=drain_response,
                        evidence={
                            "subscription_id": compat_subscription_id,
                            "drained_event_count": len(drain_events),
                            "first_kind": drain_events[0].get("kind"),
                        },
                    )
                    break
            record_compatibility_result(
                artifact,
                command="browser.unsubscribeEvents",
                response=compat_unsubscribe,
                evidence={"subscription_id": compat_subscription_id},
            )

            compat_close_page = client.request(
                "browser.closePage",
                label="compat.browser.closePage",
                browser_context_id=compat_main_context_id,
                page_id=compat_extra_page_id,
            )
            wait_for_page_absent(
                client,
                browser_context_id=compat_main_context_id,
                page_id=compat_extra_page_id,
                timeout_ms=args.page_timeout_ms,
                label="compat-close-page",
            )
            record_compatibility_result(
                artifact,
                command="browser.closePage",
                response=compat_close_page,
                evidence={"page_id": compat_extra_page_id},
            )

            compat_close_context = client.request(
                "browser.closeContext",
                label="compat.browser.closeContext",
                browser_context_id=compat_tab_create_id,
            )
            wait_for_context_absent(
                client,
                browser_context_id=compat_tab_create_id,
                timeout_ms=args.page_timeout_ms,
                label="compat-close-context",
            )
            record_compatibility_result(
                artifact,
                command="browser.closeContext",
                response=compat_close_context,
                evidence={"context_id": compat_tab_create_id},
            )

            client.request(
                "browser.context.close",
                label="compat.browser.context.close.cleanup-new-tab",
                browser_context_id=compat_new_tab_id,
            )
            wait_for_context_absent(
                client,
                browser_context_id=compat_new_tab_id,
                timeout_ms=args.page_timeout_ms,
                label="compat-cleanup-new-tab",
            )
            client.request(
                "browser.context.close",
                label="compat.browser.context.close.cleanup-main",
                browser_context_id=compat_main_context_id,
            )
            wait_for_context_absent(
                client,
                browser_context_id=compat_main_context_id,
                timeout_ms=args.page_timeout_ms,
                label="compat-cleanup-main",
            )

            compatibility_actual_commands = {
                entry["command"] for entry in artifact.get("compatibility_matrix", [])
            }
            require(
                compatibility_actual_commands == compatibility_expected_commands,
                "browser compatibility matrix coverage mismatch: "
                f"missing={sorted(compatibility_expected_commands - compatibility_actual_commands)} "
                f"extra={sorted(compatibility_actual_commands - compatibility_expected_commands)}",
            )

            event_unsubscribe = client.request(
                "browser.event.unsubscribe",
                browser_tab_id=main_context_id,
                label="browser.event.unsubscribe.main",
                payload={"subscriptionID": subscription_id},
            )

            close_extra_page = client.request(
                "browser.page.close",
                browser_context_id=main_context_id,
                page_id=extra_page_id,
                label="browser.page.close.extra",
            )
            wait_for_page_absent(
                client,
                browser_context_id=main_context_id,
                page_id=extra_page_id,
                timeout_ms=args.page_timeout_ms,
                label="extra-page-closed",
            )

            close_compat_context = client.request(
                "browser.context.close",
                browser_context_id=compat_tab_id,
                label="browser.context.close.compat",
            )
            wait_for_context_absent(
                client,
                browser_context_id=compat_tab_id,
                timeout_ms=args.page_timeout_ms,
                label="compat-context-closed",
            )

            close_main_context = client.request(
                "browser.context.close",
                browser_context_id=main_context_id,
                label="browser.context.close.main",
            )
            final_contexts = wait_for_context_absent(
                client,
                browser_context_id=main_context_id,
                timeout_ms=args.page_timeout_ms,
                label="main-context-closed",
            )

            require(debug_status["result"]["cefInitialized"] is True, "CEF was not initialized")
            require(debug_status["result"]["runtimeAvailable"] is True, "Browser runtime was not available")
            require(str(context_get["result"]["id"]) == main_context_id, "context.get did not return the main context")
            require(str(page_get_active["result"]["id"]) == main_page_id, "page.getActive did not return the main page")
            require(any(str(page.get("id")) == main_page_id for page in page_list["result"]), "page.list omitted the main page")
            require(any(bool(frame.get("isMainFrame")) for frame in frame_list["result"]), "frame.list omitted the main frame")
            require(any(str(tab.get("id")) == main_context_id for tab in tab_list_initial["result"]), "tab.list omitted the main tab")
            require(active_main_context["isFrontmost"] is True, "context.activate did not make the main context frontmost")
            require(any(str(page.get("id")) == extra_page_id for page in page_list_with_extra["result"]), "page.new did not create the extra page")
            require(load_second["result"]["loaded"] is True, "page.load did not report success")
            require(
                page_back["result"]["accepted"] is True and page_back["result"]["operation"] == "goBack",
                "page.back did not report the expected acknowledgment",
            )
            require(
                page_forward["result"]["accepted"] is True and page_forward["result"]["operation"] == "goForward",
                "page.forward did not report the expected acknowledgment",
            )
            require(
                page_reload["result"]["accepted"] is True and page_reload["result"]["operation"] == "reload",
                "page.reload did not report the expected acknowledgment",
            )
            require(dom_query["result"]["found"] is True, "dom.query did not find #click-target")
            require(dom_click["result"]["clicked"] is True, "dom.click did not click #click-target")
            require(dom_type["result"]["typed"] is True and dom_type["result"]["value"] == "Leon", "dom.type did not set the expected value")
            require(dom_get_text["result"]["text"] == "clicked", "dom.getText did not observe the clicked status")
            require(dom_get_attributes["result"]["attributes"]["data-role"] == "action", "dom.getAttributes did not expose the expected data-role")
            require((dom_get_bounding_box["result"]["width"] or 0) > 0, "dom.getBoundingBox width was not positive")
            require(dom_snapshot["result"]["found"] is True and dom_snapshot["result"]["snapshot"] is not None, "dom.snapshot did not return a snapshot")
            require(len(dom_batch["result"]["results"]) == len(batch_commands), "dom.batch result count did not match commandsJSON")
            require(json.loads(dom_eval["result"])["notificationSupported"] is True, "dom.eval state did not parse correctly")
            cookie_names_after_set = {entry["name"] for entry in cookie_get["result"]["cookies"]}
            require("session_token" in cookie_names_after_set, "cookie.set/cookie.get did not surface session_token")
            cookie_names_after_delete = {entry["name"] for entry in cookie_get_after_delete["result"]["cookies"]}
            require("session_token" not in cookie_names_after_delete, "cookie.delete did not remove session_token")
            cookie_names_after_clear = {entry["name"] for entry in cookie_get_after_clear["result"]["cookies"]}
            require("clear_me" not in cookie_names_after_clear, "cookie.clear did not remove clear_me")
            require(dialog_resolve["result"]["resolved"] is True, "resolveDialog did not acknowledge success")
            require(json.loads(dialog_state["result"])["alertDone"] is True, "alert resolution did not update page state")
            require(json.loads(permission_state_before["result"])["notificationSupported"] is True, "Notification API was unavailable in the fixture page")
            require(permission_resolve["result"]["resolved"] is True, "resolvePermission did not acknowledge success")
            require(json.loads(permission_state_after)["notificationResult"] == "granted", "permission resolution did not grant notifications")
            require(auth_resolve["result"]["resolved"] is True, "resolveAuth did not acknowledge success")
            require(len(auth_responsive) >= 3, "Browser control never restabilized after auth resolution")
            require(auth_ready["found"] is True, "Auth page never became ready")
            require(any(entry["authorization"] for entry in auth_server["request_log"]), "Auth server never observed credentials")
            require(cert_resolve["result"]["resolved"] is True, "resolveCertificate did not acknowledge success")
            require(len(cert_responsive) >= 3, "Browser control never restabilized after certificate resolution")
            require(cert_ready["found"] is True, "Certificate page never became ready")
            require(download_cancel["result"]["accepted"] is True, "download.cancel was not accepted")
            require(download_canceled["event"]["payload"]["downloadID"] == download_id, "download cancel event had the wrong downloadID")
            require(event_unsubscribe["result"]["ok"] is True, "event.unsubscribe did not acknowledge success")
            require(int(close_extra_page["result"]["remainingPageCount"]) == 1, "page.close did not leave one main page")
            require(int(close_compat_context["result"]["closedPageCount"]) >= 1, "context.close compat did not report closed pages")
            require(int(close_main_context["result"]["closedPageCount"]) >= 1, "context.close main did not report closed pages")

            artifact["summary"] = {
                "main_context_id": main_context_id,
                "main_page_id": main_page_id,
                "compat_context_id": compat_tab_id,
                "extra_page_id": extra_page_id,
                "download_id": download_id,
                "initial_context_count": len(initial_contexts.get("result") or []),
                "final_context_count": len(final_contexts),
                "download_server_bytes_sent": fixture_server["download_state"]["bytes_sent"],
                "download_server_completed": fixture_server["download_state"]["completed"],
                "auth_request_count": len(auth_server["request_log"]),
            }

            artifact["key_results"] = {
                "debug_status": debug_status["result"],
                "context_get": context_get["result"],
                "page_get_active": page_get_active["result"],
                "frame_count": len(frame_list["result"]),
                "cookie_names_after_set": sorted(cookie_names_after_set),
                "cookie_names_after_delete": sorted(cookie_names_after_delete),
                "cookie_names_after_clear": sorted(cookie_names_after_clear),
                "navigation_event": nav_event["event"],
                "page_inspection_event": page_inspection_event["event"],
                "dialog_requested": dialog_requested["event"],
                "permission_requested": permission_requested["event"],
                "auth_requested": auth_requested["event"],
                "certificate_requested": cert_requested["event"],
                "download_started": download_started["event"],
                "download_canceled": download_canceled["event"],
            }
            artifact["compatibility_summary"] = {
                "command_count": len(artifact.get("compatibility_matrix", [])),
                "commands": [entry["command"] for entry in artifact.get("compatibility_matrix", [])],
                "navigation_event": compat_nav_event,
                "compat_download_id": compat_download_id,
            }

            artifact["status"] = "passed"
            write_artifact(output_path, artifact)

    except Exception as exc:  # noqa: BLE001
        artifact["status"] = "failed"
        artifact["error"] = str(exc)
        artifact["log_tail"] = tail_text(log_path)
        write_artifact(output_path, artifact)
        skip_cleanup = bool(args.keep_failed_session)
        raise
    finally:
        if proc is not None and pid_is_alive(proc.pid):
            try:
                terminate_process(proc)
            except Exception as terminate_error:  # noqa: BLE001
                artifact.setdefault("cleanup_errors", []).append(str(terminate_error))
                write_artifact(output_path, artifact)
        if session_root.exists() and not skip_cleanup:
            shutil.rmtree(session_root, ignore_errors=True)

    return artifact


def main() -> None:
    args = parse_args()
    run_acceptance(args)


if __name__ == "__main__":
    main()
