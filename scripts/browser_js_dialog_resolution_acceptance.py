#!/usr/bin/env python3

"""
Browser JavaScript dialog resolution acceptance harness.

This harness launches an isolated CEF-enabled GhoDex app, serves a
deterministic local page, exercises alert/confirm/prompt flows through
`browser.tab.v1`, resolves them externally with `resolveDialog`, and archives
the observed `javaScriptDialog` envelopes plus page-visible outcomes.

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
DEFAULT_OUTPUT = "/tmp/ghx-browser-js-dialog-resolution-acceptance.json"


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
        description="Prove external resolveDialog handling for Browser JavaScript dialogs."
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
        help="Timeout for socket, page, and dialog resolution readiness.",
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
def local_dialog_server() -> dict[str, str]:
    webroot = Path(tempfile.mkdtemp(prefix="ghodex-browser-dialog-web-"))
    main_html = """<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <title>js-dialog-resolution-main</title>
  </head>
  <body>
    <h1 id="ready-marker">js-dialog-resolution-main</h1>
    <script>
      window.__ghodexDialogHarness = {
        alertDone: false,
        confirmResult: null,
        promptResult: null
      };

      window.__ghodexScheduleAlert = function() {
        setTimeout(() => {
          alert("alert from harness");
          window.__ghodexDialogHarness.alertDone = true;
        }, 0);
      };

      window.__ghodexScheduleConfirm = function() {
        setTimeout(() => {
          window.__ghodexDialogHarness.confirmResult = confirm("confirm from harness");
        }, 0);
      };

      window.__ghodexSchedulePrompt = function() {
        setTimeout(() => {
          window.__ghodexDialogHarness.promptResult = prompt("prompt from harness", "anon");
        }, 0);
      };
    </script>
  </body>
</html>
"""
    (webroot / "index.html").write_text(main_html, encoding="utf-8")

    class QuietHandler(http.server.SimpleHTTPRequestHandler):
        def log_message(self, format: str, *args) -> None:  # noqa: A003
            return

    previous_cwd = os.getcwd()
    os.chdir(webroot)
    try:
        with socketserver.TCPServer(("127.0.0.1", 0), QuietHandler) as server:
            port = server.server_address[1]
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                yield {
                    "root": str(webroot),
                    "port": str(port),
                    "main_url": f"http://127.0.0.1:{port}/index.html",
                }
            finally:
                server.shutdown()
                server.server_close()
                thread.join(timeout=5.0)
    finally:
        os.chdir(previous_cwd)
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


def create_context_with_retry(
    socket_path: str,
    *,
    url: str,
    timeout_ms: int,
) -> dict:
    deadline = time.monotonic() + (timeout_ms / 1000.0)
    last_error: str | None = None
    while time.monotonic() < deadline:
        remaining = max(10.0, deadline - time.monotonic())
        try:
            return send_request(
                socket_path,
                "newContext",
                version="browser.context.v2",
                payload={"url": url},
                timeout=max(command_timeout_seconds(timeout_ms), remaining + 5.0),
            )
        except Exception as exc:  # noqa: BLE001
            last_error = str(exc)
            time.sleep(0.5)
    raise RuntimeError(f"Timed out waiting for newContext response: {last_error or 'unknown error'}")


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


def wait_for_dialog_event(
    socket_path: str,
    subscription_id: str,
    *,
    phase: str,
    dialog_type: str,
    page_id: str,
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
            if event.get("kind") != "javaScriptDialog":
                continue
            payload = event.get("payload", {})
            if payload.get("pageID") != page_id:
                continue
            if payload.get("phase") != phase:
                continue
            if payload.get("dialogType") != dialog_type:
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
        f"Timed out waiting for javaScriptDialog phase={phase} dialogType={dialog_type} requestID={request_id!r}"
    )


def wait_for_harness_state(
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
            "JSON.stringify(window.__ghodexDialogHarness)",
        )
        last_value = state.get(field)
        if last_value == expected_value:
            return state
        time.sleep(0.25)
    raise RuntimeError(
        f"Timed out waiting for dialog harness field {field} == {expected_value!r}; last value was {last_value!r}"
    )


def schedule_dialog(
    socket_path: str,
    browser_tab_id: str,
    page_id: str,
    function_name: str,
) -> dict:
    return send_request(
        socket_path,
        "evaluateJavaScript",
        browser_tab_id=browser_tab_id,
        page_id=page_id,
        payload={"script": f"{function_name}(); JSON.stringify({{'scheduled': true}})"},
        timeout=20.0,
    )


def run_acceptance(args: argparse.Namespace) -> dict:
    app_bundle = Path(args.app).resolve() if args.app else resolve_default_app()
    runtime_root = str(Path(args.runtime_root).resolve())
    output_path = Path(args.output).expanduser().resolve()

    session_root = Path(f"/tmp/ghx-dialogevt-{uuid.uuid4().hex[:8]}")
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
        with local_dialog_server() as server_info:
            artifact["server"] = server_info
            proc = launch_app(
                app_bundle,
                log_path,
                runtime_root=runtime_root,
                app_support_root=app_support_root,
                home_dir=home_dir,
            )
            artifact["pid"] = proc.pid

            socket_ready = wait_for_socket_ready(str(socket_path), args.page_timeout_ms)
            artifact["socket_ready"] = socket_ready

            command_timeout = max(45.0, args.page_timeout_ms / 1000.0)
            contexts_before = wait_for_context_list(str(socket_path), args.page_timeout_ms)
            previous_context_ids = {str(context["id"]) for context in contexts_before}

            create_context = create_context_with_retry(
                str(socket_path),
                url=server_info["main_url"],
                timeout_ms=args.page_timeout_ms,
            )
            if create_context["response"].get("ok") is True:
                context_summary = extract_result_json(create_context["response"])
                if not isinstance(context_summary, dict):
                    raise RuntimeError(f"Expected newContext to return a dict, got {context_summary!r}")
            else:
                error = create_context["response"].get("error") or {}
                if error.get("code") != "bridgeUnavailable":
                    raise RuntimeError(
                        f"newContext failed unexpectedly: {json.dumps(create_context['response'], sort_keys=True)}"
                    )
                context_summary = wait_for_new_context(str(socket_path), previous_context_ids, args.page_timeout_ms)

            browser_tab_id = str(context_summary["id"])
            page_id = str(context_summary["activePageID"])
            initial_bridge_ready = wait_for_selector(
                str(socket_path),
                browser_tab_id,
                page_id,
                "#ready-marker",
                args.page_timeout_ms,
            )

            subscription = extract_result_json(
                send_request(
                    str(socket_path),
                    "subscribeEvents",
                    browser_tab_id=browser_tab_id,
                    payload={"kindsJSON": json.dumps(["javaScriptDialog"])},
                )["response"]
            )
            subscription_id = subscription["subscriptionID"]
            ready_result = initial_bridge_ready

            alert_schedule = schedule_dialog(
                str(socket_path),
                browser_tab_id,
                page_id,
                "window.__ghodexScheduleAlert",
            )
            alert_requested = wait_for_dialog_event(
                str(socket_path),
                subscription_id,
                phase="requested",
                dialog_type="alert",
                page_id=page_id,
                timeout_ms=args.page_timeout_ms,
            )
            alert_request_id = alert_requested["event"]["payload"]["requestID"]
            alert_resolve = send_request(
                str(socket_path),
                "resolveDialog",
                browser_tab_id=browser_tab_id,
                page_id=page_id,
                payload={"requestID": alert_request_id, "accepted": "true"},
            )
            alert_resolved = wait_for_dialog_event(
                str(socket_path),
                subscription_id,
                phase="resolved",
                dialog_type="alert",
                page_id=page_id,
                request_id=alert_request_id,
                timeout_ms=args.page_timeout_ms,
            )
            alert_state = wait_for_harness_state(
                str(socket_path),
                browser_tab_id,
                page_id,
                field="alertDone",
                expected_value=True,
                timeout_ms=args.page_timeout_ms,
            )

            stale_alert_retry = send_request(
                str(socket_path),
                "resolveDialog",
                browser_tab_id=browser_tab_id,
                page_id=page_id,
                payload={"requestID": alert_request_id, "accepted": "true"},
            )
            stale_error = stale_alert_retry["response"].get("error") or {}
            stale_error_code = stale_error.get("code")
            if stale_alert_retry["response"].get("ok") is not False or stale_error_code not in {"invalid_request", "invalidRequest"}:
                raise RuntimeError(
                    "Expected stale resolveDialog retry to fail with invalidRequest, "
                    f"got {json.dumps(stale_alert_retry['response'], sort_keys=True)}"
                )

            confirm_schedule = schedule_dialog(
                str(socket_path),
                browser_tab_id,
                page_id,
                "window.__ghodexScheduleConfirm",
            )
            confirm_requested = wait_for_dialog_event(
                str(socket_path),
                subscription_id,
                phase="requested",
                dialog_type="confirm",
                page_id=page_id,
                timeout_ms=args.page_timeout_ms,
            )
            confirm_request_id = confirm_requested["event"]["payload"]["requestID"]
            confirm_resolve = send_request(
                str(socket_path),
                "resolveDialog",
                browser_tab_id=browser_tab_id,
                page_id=page_id,
                payload={"requestID": confirm_request_id, "accepted": "false"},
            )
            confirm_resolved = wait_for_dialog_event(
                str(socket_path),
                subscription_id,
                phase="resolved",
                dialog_type="confirm",
                page_id=page_id,
                request_id=confirm_request_id,
                timeout_ms=args.page_timeout_ms,
            )
            confirm_state = wait_for_harness_state(
                str(socket_path),
                browser_tab_id,
                page_id,
                field="confirmResult",
                expected_value=False,
                timeout_ms=args.page_timeout_ms,
            )

            prompt_schedule = schedule_dialog(
                str(socket_path),
                browser_tab_id,
                page_id,
                "window.__ghodexSchedulePrompt",
            )
            prompt_requested = wait_for_dialog_event(
                str(socket_path),
                subscription_id,
                phase="requested",
                dialog_type="prompt",
                page_id=page_id,
                timeout_ms=args.page_timeout_ms,
            )
            prompt_request_id = prompt_requested["event"]["payload"]["requestID"]
            prompt_resolve = send_request(
                str(socket_path),
                "resolveDialog",
                browser_tab_id=browser_tab_id,
                page_id=page_id,
                payload={
                    "requestID": prompt_request_id,
                    "accepted": "true",
                    "userInput": "Leon",
                },
            )
            prompt_resolved = wait_for_dialog_event(
                str(socket_path),
                subscription_id,
                phase="resolved",
                dialog_type="prompt",
                page_id=page_id,
                request_id=prompt_request_id,
                timeout_ms=args.page_timeout_ms,
            )
            prompt_state = wait_for_harness_state(
                str(socket_path),
                browser_tab_id,
                page_id,
                field="promptResult",
                expected_value="Leon",
                timeout_ms=args.page_timeout_ms,
            )

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
                    "pageID": page_id,
                    "createContext": create_context,
                    "contextSummary": context_summary,
                    "initialBridgeReady": initial_bridge_ready,
                    "subscription": subscription,
                    "readyResult": ready_result,
                    "alertFlow": {
                        "scheduled": alert_schedule,
                        "requested": alert_requested["event"],
                        "resolved": alert_resolved["event"],
                        "resolveResult": extract_result_json(alert_resolve["response"]),
                        "pageState": alert_state,
                        "staleRetry": stale_alert_retry,
                    },
                    "confirmFlow": {
                        "scheduled": confirm_schedule,
                        "requested": confirm_requested["event"],
                        "resolved": confirm_resolved["event"],
                        "resolveResult": extract_result_json(confirm_resolve["response"]),
                        "pageState": confirm_state,
                    },
                    "promptFlow": {
                        "scheduled": prompt_schedule,
                        "requested": prompt_requested["event"],
                        "resolved": prompt_resolved["event"],
                        "resolveResult": extract_result_json(prompt_resolve["response"]),
                        "pageState": prompt_state,
                    },
                    "finalDrain": final_drain,
                    "unsubscribeResult": unsubscribe_result,
                    "expectations": {
                        "staleRetryErrorCode": "invalid_request",
                        "confirmResolvedAccepted": "false",
                        "promptResolvedUserInput": "Leon",
                    },
                }
            )
    except Exception as exc:  # noqa: BLE001
        artifact["status"] = "failed"
        artifact["error"] = str(exc)
        raise
    finally:
        if proc is not None:
            terminate_process(proc)
        if socket_path.exists():
            wait_for_socket_gone(str(socket_path), 10000)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(json.dumps(artifact, indent=2, sort_keys=True), encoding="utf-8")

    return artifact


def main() -> None:
    args = parse_args()
    artifact = run_acceptance(args)
    print(json.dumps(artifact, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
