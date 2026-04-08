#!/usr/bin/env python3

"""
Browser cookie persistence acceptance harness.

This harness launches a CEF-enabled GhoDex app against a local HTTP page, writes
one unique cookie through the Browser control plane, restarts the app, and
verifies that the cookie persists when the same profile is reused.

By default it exercises both:
- managed profile mode (no external profile override)
- external profile mode (config-driven Chromium-style profile directory)

Safety note:
- by default the harness launches the test app against an isolated Browser app-
  support root, so its managed profile and Browser IPC socket do not overlap
  with a running `/Applications/GhoDex.app`
- if `--socket` points at a shared live socket, the harness will refuse to run
  unless `--allow-existing-ghodex` is explicitly passed
"""

from __future__ import annotations

import argparse
import http.server
import json
import os
import re
import shutil
import socket
import socketserver
import subprocess
import sys
import tempfile
import threading
import time
import uuid
from contextlib import contextmanager
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = "/tmp/ghodex-browser-cookie-persistence-acceptance.json"
CEF_INIT_RE = re.compile(
    r"\[CEF\] Initializing framework=(?P<framework>.+?) "
    r"profile=(?P<profile>.+?) cache=(?P<cache>.+?) "
    r"external_profile=(?P<external_profile>.+?) bundle="
)


def default_shared_socket_path() -> str:
    home = Path.home()
    return str(home / "Library" / "Application Support" / "GhoDex" / "browser-control.sock")


def resolve_default_app() -> Path:
    candidates: list[Path] = []
    candidates.extend(REPO_ROOT.glob("macos/build-managed-cef*/Debug/GhoDex.app"))

    default_debug_app = REPO_ROOT / "macos/build/Debug/GhoDex.app"
    if default_debug_app.exists():
        candidates.append(default_debug_app)

    candidates = sorted(
        candidates,
        key=lambda path: path.stat().st_mtime,
        reverse=True,
    )
    if not candidates:
        raise SystemExit(
            "No built GhoDex.app found under macos/build-managed-cef*/Debug "
            "or macos/build/Debug/GhoDex.app. "
            "Pass --app=/path/to/GhoDex.app."
        )
    return candidates[0]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Verify Browser cookie persistence across app restarts."
    )
    parser.add_argument(
        "--app",
        default=None,
        help=(
            "Path to the CEF-enabled GhoDex.app bundle to launch; defaults to the "
            "newest macos/build-managed-cef*/Debug/GhoDex.app or "
            "macos/build/Debug/GhoDex.app"
        ),
    )
    parser.add_argument(
        "--runtime-root",
        default=str(REPO_ROOT / "macos/build/cef-runtime/current"),
        help="CEF runtime root written into the generated config file",
    )
    parser.add_argument(
        "--socket",
        default=None,
        help="Path to browser-control.sock; defaults to an isolated socket under the harness workspace",
    )
    parser.add_argument(
        "--profile-mode",
        choices=["managed", "external", "all"],
        default="all",
        help="Which profile mode(s) to exercise",
    )
    parser.add_argument(
        "--page-timeout-ms",
        type=int,
        default=30000,
        help="Timeout for socket readiness, page readiness, and cookie checks",
    )
    parser.add_argument(
        "--output",
        default=DEFAULT_OUTPUT,
        help="Where to write the JSON artifact",
    )
    parser.add_argument(
        "--allow-existing-ghodex",
        action="store_true",
        help="Allow the harness to run even if another GhoDex process or Browser IPC socket already exists",
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
    payload: dict[str, str] | None = None,
    timeout: float = 10.0,
) -> dict:
    body = {
        "id": str(uuid.uuid4()),
        "version": version,
        "command": command,
        "payload": payload or {},
    }
    if browser_tab_id is not None:
        body["browserTabID"] = browser_tab_id

    started = time.perf_counter()
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(timeout)
    client.connect(socket_path)
    client.sendall((json.dumps(body) + "\n").encode())
    line = recv_line(client)
    client.close()
    elapsed_ms = round((time.perf_counter() - started) * 1000, 2)
    return {"elapsed_ms": elapsed_ms, "request": body, "response": json.loads(line)}


def extract_result_json(response: dict) -> dict:
    if response.get("ok") is not True:
        raise RuntimeError(f"request failed: {json.dumps(response, sort_keys=True)}")
    raw = response.get("resultJSON")
    if not isinstance(raw, str):
        raise RuntimeError(f"missing resultJSON in response: {json.dumps(response, sort_keys=True)}")
    return json.loads(raw)


def run(command: list[str], *, check: bool = True, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    proc = subprocess.run(command, text=True, capture_output=True, env=env)
    if check and proc.returncode != 0:
        raise RuntimeError(
            f"command failed: {' '.join(command)}\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
        )
    return proc


def running_ghodex_processes() -> list[str]:
    proc = run(["ps", "-Ao", "pid=,command="], check=True)
    lines = []
    for line in proc.stdout.splitlines():
        if "GhoDex.app/Contents/MacOS/GhoDex" in line:
            lines.append(line.strip())
    return lines


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


def wait_for_context_list(
    socket_path: str,
    timeout_ms: int,
) -> list[dict]:
    deadline = time.monotonic() + (timeout_ms / 1000.0)
    last_error: str | None = None
    while time.monotonic() < deadline:
        try:
            result = extract_result_json(
                send_request(
                    socket_path,
                    "listContexts",
                    version="browser.context.v2",
                    payload={},
                    timeout=10.0,
                )["response"]
            )
            if not isinstance(result, list):
                raise RuntimeError(f"Expected listContexts to return a list, got {result!r}")
            return result
        except Exception as exc:  # noqa: BLE001
            last_error = str(exc)
            time.sleep(0.5)
    raise RuntimeError(f"Timed out waiting for listContexts readiness: {last_error or 'unknown error'}")


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
                payload={},
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


def create_context_with_retry(
    socket_path: str,
    *,
    page_url: str,
    timeout_ms: int,
) -> tuple[dict, dict]:
    previous_context_ids = {
        str(context.get("id", ""))
        for context in wait_for_context_list(socket_path, timeout_ms)
        if str(context.get("id", ""))
    }
    deadline = time.monotonic() + (timeout_ms / 1000.0)
    last_error: str | None = None

    while time.monotonic() < deadline:
        remaining = max(10.0, deadline - time.monotonic())
        try:
            create_context = send_request(
                socket_path,
                "newContext",
                version="browser.context.v2",
                payload={"url": page_url},
                timeout=max(command_timeout_seconds(timeout_ms), remaining + 5.0),
            )
        except Exception as exc:  # noqa: BLE001
            last_error = str(exc)
            time.sleep(0.5)
            continue

        if create_context["response"].get("ok") is True:
            context_summary = extract_result_json(create_context["response"])
            if not isinstance(context_summary, dict):
                raise RuntimeError(f"Expected newContext to return an object, got {context_summary!r}")
            return create_context, context_summary

        error = create_context["response"].get("error") or {}
        if error.get("code") not in {"bridgeUnavailable", "requestTimedOut"}:
            raise RuntimeError(
                f"newContext failed unexpectedly: {json.dumps(create_context['response'], sort_keys=True)}"
            )

        context_summary = wait_for_new_context(socket_path, previous_context_ids, timeout_ms)
        return create_context, context_summary

    raise RuntimeError(f"Timed out waiting for newContext response: {last_error or 'unknown error'}")


def parse_single_cef_init_log(text: str) -> dict:
    matches = list(CEF_INIT_RE.finditer(text))
    if len(matches) != 1:
        raise RuntimeError(f"Expected exactly one CEF initialization line, found {len(matches)}")
    values = matches[0].groupdict()
    external_profile = values["external_profile"]
    if external_profile == "<none>":
        external_profile = None
    return {
        "framework": values["framework"],
        "profile": values["profile"],
        "cache": values["cache"],
        "external_profile": external_profile,
    }


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
    profile_path: str | None,
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
    if profile_path is not None:
        env["GHODEX_CEF_PROFILE_PATH"] = profile_path
    else:
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
def local_cookie_server() -> dict[str, str]:
    webroot = Path(tempfile.mkdtemp(prefix="ghodex-browser-cookie-web-"))
    page = """<!doctype html>
<html>
  <head><meta charset="utf-8"><title>cookie-test</title></head>
  <body>
    <h1 id="marker">cookie-test</h1>
    <script>
      window.__ghodexCookieHarnessReady = true;
    </script>
  </body>
</html>
"""
    (webroot / "cookie.html").write_text(page, encoding="utf-8")

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
        yield {
            "page_url": f"http://127.0.0.1:{server.server_address[1]}/cookie.html",
            "webroot": str(webroot),
        }
    finally:
        server.shutdown()
        server.server_close()
        shutil.rmtree(webroot, ignore_errors=True)


def wait_for_page_ready(socket_path: str, browser_tab_id: str, expected_url: str, timeout_ms: int) -> dict:
    deadline = time.monotonic() + (timeout_ms / 1000.0)
    last_error: str | None = None
    last_response: dict | None = None
    script = """
(() => ({
  href: location.href,
  readyState: document.readyState,
  ready: window.__ghodexCookieHarnessReady === true,
  cookie: document.cookie
}))()
""".strip()
    while time.monotonic() < deadline:
        remaining_ms = max(1000, int((deadline - time.monotonic()) * 1000))
        try:
            response = send_request(
                socket_path,
                "evaluateJavaScript",
                browser_tab_id=browser_tab_id,
                payload={"script": script},
                timeout=max(20.0, min(remaining_ms, 5000) / 1000.0 + 5.0),
            )
        except TimeoutError as exc:
            last_error = str(exc)
            time.sleep(0.25)
            continue

        last_response = response["response"]
        if response["response"].get("ok") is True:
            result = extract_result_json(response["response"])
            if (
                isinstance(result, dict)
                and result.get("href") == expected_url
                and result.get("readyState") == "complete"
                and result.get("ready") is True
            ):
                return result
        time.sleep(0.25)
    raise RuntimeError(
        f"Timed out waiting for page readiness for {expected_url}; "
        f"last_error={last_error!r}; last_response={json.dumps(last_response or {}, sort_keys=True)}"
    )


def cookie_value_from_header(cookie_header: str, cookie_name: str) -> str | None:
    for part in cookie_header.split(";"):
        stripped = part.strip()
        if stripped.startswith(f"{cookie_name}="):
            return stripped.split("=", 1)[1]
    return None


def set_cookie(
    socket_path: str,
    browser_tab_id: str,
    cookie_name: str,
    cookie_value: str,
    timeout_ms: int,
) -> dict:
    command_timeout = command_timeout_seconds(timeout_ms)
    script = f"""
(() => {{
  document.cookie = {json.dumps(cookie_name + "=" + cookie_value + "; path=/; max-age=86400; SameSite=Lax")};
  return {{
    cookieHeader: document.cookie,
    cookieValue: (() => {{
      const prefix = {json.dumps(cookie_name + "=")};
      for (const part of document.cookie.split(';')) {{
        const stripped = part.trim();
        if (stripped.startsWith(prefix)) return stripped.slice(prefix.length);
      }}
      return null;
    }})()
  }};
}})()
""".strip()
    response = send_request(
        socket_path,
        "evaluateJavaScript",
        browser_tab_id=browser_tab_id,
        payload={"script": script},
        timeout=command_timeout,
    )
    return extract_result_json(response["response"])


def read_cookie(
    socket_path: str,
    browser_tab_id: str,
    cookie_name: str,
    timeout_ms: int,
) -> dict:
    command_timeout = command_timeout_seconds(timeout_ms)
    script = f"""
(() => {{
  const prefix = {json.dumps(cookie_name + "=")};
  let cookieValue = null;
  for (const part of document.cookie.split(';')) {{
    const stripped = part.trim();
    if (stripped.startsWith(prefix)) {{
      cookieValue = stripped.slice(prefix.length);
      break;
    }}
  }}
  return {{
    cookieHeader: document.cookie,
    cookieValue
  }};
}})()
""".strip()
    response = send_request(
        socket_path,
        "evaluateJavaScript",
        browser_tab_id=browser_tab_id,
        payload={"script": script},
        timeout=command_timeout,
    )
    return extract_result_json(response["response"])


def clear_cookie(
    socket_path: str,
    browser_tab_id: str,
    cookie_name: str,
    timeout_ms: int,
) -> dict:
    command_timeout = command_timeout_seconds(timeout_ms)
    script = f"""
(() => {{
  document.cookie = {json.dumps(cookie_name + '=; path=/; max-age=0; SameSite=Lax')};
  return {{
    cookieHeader: document.cookie
  }};
}})()
""".strip()
    response = send_request(
        socket_path,
        "evaluateJavaScript",
        browser_tab_id=browser_tab_id,
        payload={"script": script},
        timeout=command_timeout,
    )
    return extract_result_json(response["response"])


def exercise_cookie_roundtrip(
    socket_path: str,
    page_url: str,
    cookie_name: str,
    cookie_value: str,
    timeout_ms: int,
) -> dict:
    new_context, context_summary = create_context_with_retry(
        socket_path,
        page_url=page_url,
        timeout_ms=timeout_ms,
    )
    browser_tab_id = context_summary["id"]
    first_ready = wait_for_page_ready(socket_path, browser_tab_id, page_url, timeout_ms)
    write_result = set_cookie(socket_path, browser_tab_id, cookie_name, cookie_value, timeout_ms)
    read_back = read_cookie(socket_path, browser_tab_id, cookie_name, timeout_ms)
    return {
        "browser_tab_id": browser_tab_id,
        "create_context": context_summary,
        "initial_page": first_ready,
        "write_result": write_result,
        "read_back": read_back,
    }


def cleanup_cookie(
    socket_path: str,
    page_url: str,
    cookie_name: str,
    timeout_ms: int,
) -> dict:
    new_context, context_summary = create_context_with_retry(
        socket_path,
        page_url=page_url,
        timeout_ms=timeout_ms,
    )
    browser_tab_id = context_summary["id"]
    wait_for_page_ready(socket_path, browser_tab_id, page_url, timeout_ms)
    clear_result = clear_cookie(socket_path, browser_tab_id, cookie_name, timeout_ms)
    after_clear = read_cookie(socket_path, browser_tab_id, cookie_name, timeout_ms)
    return {
        "browser_tab_id": browser_tab_id,
        "create_context": context_summary,
        "clear_result": clear_result,
        "after_clear": after_clear,
    }


def run_mode(
    mode: str,
    *,
    app_bundle: Path,
    runtime_root: str,
    page_url: str,
    timeout_ms: int,
    workspace: Path,
) -> dict:
    mode_workspace = workspace / mode
    mode_workspace.mkdir(parents=True, exist_ok=True)
    app_support_root = mode_workspace / "app-support"
    home_dir = mode_workspace / "home"
    socket_path = str(app_support_root / "browser-control.sock")
    log_first = mode_workspace / "launch-1.log"
    log_second = mode_workspace / "launch-2.log"
    cookie_name = f"ghodex_cookie_{mode}_{uuid.uuid4().hex}"
    cookie_value = uuid.uuid4().hex

    if mode == "external":
        profile_path = mode_workspace / "external-profile" / "Profile 7"
        profile_path.mkdir(parents=True, exist_ok=True)
        configured_profile = str(profile_path)
    elif mode == "managed":
        configured_profile = None
    else:
        raise RuntimeError(f"Unsupported profile mode: {mode}")

    first_proc = launch_app(
        app_bundle,
        log_first,
        runtime_root=runtime_root,
        app_support_root=app_support_root,
        profile_path=configured_profile,
        home_dir=home_dir,
    )
    try:
        socket_ready = wait_for_socket_ready(socket_path, timeout_ms)
        first_roundtrip = exercise_cookie_roundtrip(
            socket_path,
            page_url,
            cookie_name,
            cookie_value,
            timeout_ms,
        )
        first_log_text = wait_for_log_substring(log_first, "[CEF] Initializing", timeout_ms)
        first_launch = parse_single_cef_init_log(first_log_text)
    finally:
        terminate_process(first_proc)
        wait_for_socket_gone(socket_path, timeout_ms)

    second_proc = launch_app(
        app_bundle,
        log_second,
        runtime_root=runtime_root,
        app_support_root=app_support_root,
        profile_path=configured_profile,
        home_dir=home_dir,
    )
    try:
        second_socket_ready = wait_for_socket_ready(socket_path, timeout_ms)
        second_roundtrip = exercise_cookie_roundtrip(
            socket_path,
            page_url,
            cookie_name,
            cookie_value,
            timeout_ms,
        )
        second_log_text = wait_for_log_substring(log_second, "[CEF] Initializing", timeout_ms)
        second_launch = parse_single_cef_init_log(second_log_text)
        cleanup = cleanup_cookie(socket_path, page_url, cookie_name, timeout_ms)
    finally:
        terminate_process(second_proc)
        wait_for_socket_gone(socket_path, timeout_ms)

    persisted_cookie = second_roundtrip["read_back"]["cookieValue"]
    return {
        "mode": mode,
        "app_support_root": str(app_support_root),
        "configured_profile_path": configured_profile,
        "cookie_name": cookie_name,
        "cookie_value": cookie_value,
        "launches": {
            "first": first_launch,
            "second": second_launch,
        },
        "socket_health": {
            "first": socket_ready["response"].get("ok") is True,
            "second": second_socket_ready["response"].get("ok") is True,
        },
        "roundtrip": {
            "first_launch": first_roundtrip,
            "second_launch": second_roundtrip,
            "cleanup": cleanup,
        },
        "acceptance": {
            "first_write_visible": first_roundtrip["read_back"]["cookieValue"] == cookie_value,
            "second_read_matches": persisted_cookie == cookie_value,
            "cleanup_removed_cookie": cleanup["after_clear"]["cookieValue"] is None,
            "managed_profile_used": mode != "managed" or first_launch["external_profile"] is None,
            "external_profile_used": mode != "external" or first_launch["external_profile"] == configured_profile,
        },
        "artifacts": {
            "first_log": str(log_first),
            "second_log": str(log_second),
        },
    }


def main() -> int:
    args = parse_args()
    app_bundle = Path(os.path.expanduser(args.app)).resolve() if args.app else resolve_default_app().resolve()
    runtime_root = str(Path(os.path.expanduser(args.runtime_root)).resolve())
    shared_socket_path = os.path.expanduser(args.socket) if args.socket else default_shared_socket_path()

    if not app_bundle.exists():
        raise SystemExit(f"App bundle does not exist: {app_bundle}")
    if not Path(runtime_root).is_dir():
        raise SystemExit(f"Runtime root does not exist: {runtime_root}")

    existing_processes = running_ghodex_processes()
    existing_socket = os.path.exists(shared_socket_path)
    if args.socket and not args.allow_existing_ghodex and (existing_processes or existing_socket):
        raise SystemExit(
            "Refusing to run against the requested shared Browser IPC socket while another GhoDex instance or "
            "Browser IPC socket is already present. Close existing GhoDex instances first, or rerun with "
            "--allow-existing-ghodex if you intentionally want to share the live environment.\n"
            f"processes={existing_processes}\n"
            f"socket_present={existing_socket}"
        )

    profile_modes = ["managed", "external"] if args.profile_mode == "all" else [args.profile_mode]
    workspace = Path(tempfile.mkdtemp(prefix="ghx-cookie-", dir="/tmp"))

    with local_cookie_server() as server_info:
        results = [
            run_mode(
                mode,
                app_bundle=app_bundle,
                runtime_root=runtime_root,
                page_url=server_info["page_url"],
                timeout_ms=args.page_timeout_ms,
                workspace=workspace,
            )
            for mode in profile_modes
        ]

    artifact = {
        "app_bundle": str(app_bundle),
        "runtime_root": runtime_root,
        "shared_socket_path": shared_socket_path,
        "workspace": str(workspace),
        "results": results,
        "acceptance": {
            "all_modes_persisted": all(item["acceptance"]["second_read_matches"] for item in results),
            "all_modes_cleanup_removed_cookie": all(item["acceptance"]["cleanup_removed_cookie"] for item in results),
            "all_modes_socket_healthy": all(
                item["socket_health"]["first"] and item["socket_health"]["second"] for item in results
            ),
            "managed_mode_observed": all(
                item["acceptance"]["managed_profile_used"] for item in results if item["mode"] == "managed"
            ),
            "external_mode_observed": all(
                item["acceptance"]["external_profile_used"] for item in results if item["mode"] == "external"
            ),
        },
        "notes": [
            "This harness proves cookie persistence by writing one unique cookie, restarting the app, and reading the same cookie back through browser.tab.v1 evaluateJavaScript.",
            "Each mode launches the test app with an isolated Browser app-support root so the managed profile and Browser IPC socket do not overlap with /Applications/GhoDex.app.",
            "The managed-profile run intentionally uses no external profile override so the default managed profile path is exercised.",
            "The external-profile run creates a dedicated temporary Chromium-style profile directory and verifies that CEF reports it as the external profile.",
        ],
    }

    output_path = Path(args.output)
    output_path.write_text(json.dumps(artifact, indent=2), encoding="utf-8")
    print(json.dumps(artifact, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
