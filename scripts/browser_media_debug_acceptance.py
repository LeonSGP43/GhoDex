#!/usr/bin/env python3

"""
Browser media/debug acceptance harness.

This harness launches an isolated CEF-enabled GhoDex app, serves a deterministic
local media page, probes media/debug/browser-surface state through
`browser.tab.v1`, and archives the result as JSON.

Primary goals:
- prove whether remote debugging stays disabled by default at runtime
- capture real codec/media capability results, especially H.264
- record a small set of browser-surface signals useful for parity review

Safety notes:
- the harness always launches the target app with an isolated `HOME`
- it also relocates Browser runtime state through `GHODEX_BROWSER_APP_SUPPORT_ROOT`
- it never touches `/Applications/GhoDex.app` and never kills unrelated apps
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
import tempfile
import threading
import time
import uuid
from contextlib import contextmanager
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = "/tmp/ghx-browser-media-debug-acceptance.json"
CEF_INIT_RE = re.compile(
    r"\[CEF\] Initializing framework=(?P<framework>.+?) "
    r"profile=(?P<profile>.+?) cache=(?P<cache>.+?) "
    r"external_profile=(?P<external_profile>.+?) bundle=(?P<bundle>.+?) "
    r"remote_debug_port=(?P<remote_debug_port>-?\d+)"
)


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
        description="Probe Browser media/debug capability in an isolated GhoDex session."
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
        "--mode",
        choices=["managed", "external", "all"],
        default="all",
        help="Which profile mode lane(s) to probe.",
    )
    parser.add_argument(
        "--page-timeout-ms",
        type=int,
        default=45000,
        help="Timeout for socket/page/media readiness checks.",
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
    browser_tab_id: str | None = None,
    payload: dict[str, str] | None = None,
    timeout: float = 10.0,
) -> dict:
    body = {
        "id": str(uuid.uuid4()),
        "version": "browser.tab.v1",
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


def run(
    command: list[str],
    *,
    check: bool = True,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    proc = subprocess.run(command, text=True, capture_output=True, env=env)
    if check and proc.returncode != 0:
        raise RuntimeError(
            f"command failed: {' '.join(command)}\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
        )
    return proc


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
        "bundle": values["bundle"],
        "remote_debug_port": int(values["remote_debug_port"]),
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
    home_dir: Path,
    profile_path: str | None,
) -> subprocess.Popen[str]:
    executable = app_bundle / "Contents" / "MacOS" / "GhoDex"
    if not executable.exists():
        raise RuntimeError(f"App executable does not exist: {executable}")

    env = os.environ.copy()
    env["GHODEX_CEF_ROOT"] = runtime_root
    env["GHODEX_BROWSER_APP_SUPPORT_ROOT"] = str(app_support_root)
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


def ensure_h264_sample(output_path: Path) -> dict:
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg is None:
        raise RuntimeError("ffmpeg is required to generate the deterministic H.264 test asset")

    command = [
        ffmpeg,
        "-hide_banner",
        "-loglevel",
        "error",
        "-y",
        "-f",
        "lavfi",
        "-i",
        "color=c=black:s=320x180:d=1.2",
        "-f",
        "lavfi",
        "-i",
        "anullsrc=r=48000:cl=stereo",
        "-shortest",
        "-c:v",
        "libx264",
        "-profile:v",
        "baseline",
        "-level",
        "3.0",
        "-pix_fmt",
        "yuv420p",
        "-movflags",
        "+faststart",
        "-c:a",
        "aac",
        "-b:a",
        "96k",
        str(output_path),
    ]
    run(command)
    return {
        "path": str(output_path),
        "size": output_path.stat().st_size,
        "ffmpeg": ffmpeg,
        "command": command,
    }


@contextmanager
def local_media_server() -> dict[str, object]:
    webroot = Path(tempfile.mkdtemp(prefix="ghodex-browser-media-web-"))
    page = """<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <title>media-debug-test</title>
  </head>
  <body>
    <h1 id="marker">media-debug-test</h1>
    <script>
      window.__ghodexMediaHarnessReady = true;
    </script>
  </body>
</html>
"""
    (webroot / "media.html").write_text(page, encoding="utf-8")
    sample_info = ensure_h264_sample(webroot / "sample-h264-baseline.mp4")

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
            "page_url": f"http://127.0.0.1:{port}/media.html",
            "mp4_url": f"http://127.0.0.1:{port}/sample-h264-baseline.mp4",
            "sample": sample_info,
            "webroot": str(webroot),
        }
    finally:
        server.shutdown()
        server.server_close()
        shutil.rmtree(webroot, ignore_errors=True)


def wait_for_page_ready(socket_path: str, browser_tab_id: str, expected_url: str, timeout_ms: int) -> dict:
    deadline = time.monotonic() + (timeout_ms / 1000.0)
    script = """
(() => ({
  href: location.href,
  readyState: document.readyState,
  ready: window.__ghodexMediaHarnessReady === true
}))()
""".strip()
    while time.monotonic() < deadline:
        try:
            response = send_request(
                socket_path,
                "evaluateJavaScript",
                browser_tab_id=browser_tab_id,
                payload={"script": script},
                timeout=20.0,
            )
            if response["response"].get("ok") is True:
                result = extract_result_json(response["response"])
                if (
                    isinstance(result, dict)
                    and result.get("href") == expected_url
                    and result.get("readyState") == "complete"
                    and result.get("ready") is True
                ):
                    return result
        except Exception:  # noqa: BLE001
            pass
        time.sleep(0.25)
    raise RuntimeError(f"Timed out waiting for page readiness for {expected_url}")


def debug_status(socket_path: str) -> dict:
    response = send_request(socket_path, "getDebugStatus", timeout=5.0)
    return extract_result_json(response["response"])


def listening_tcp_sockets_for_pid(pid: int) -> list[str]:
    proc = run(
        [
            "lsof",
            "-Pan",
            "-p",
            str(pid),
            "-iTCP",
            "-sTCP:LISTEN",
        ],
        check=False,
    )
    if proc.returncode not in (0, 1):
        raise RuntimeError(f"lsof failed for pid {pid}: {proc.stderr}")
    return [line for line in proc.stdout.splitlines() if line.strip()]


def tcp_listener_present_for_port(lines: list[str], port: int) -> bool:
    if port <= 0:
        return False
    needle = f":{port} "
    return any(needle in line for line in lines)


def media_probe(socket_path: str, browser_tab_id: str, mp4_url: str) -> dict:
    script = f"""
(async () => {{
  const round3 = (value) => {{
    if (typeof value !== "number" || !Number.isFinite(value)) {{
      return null;
    }}
    return Math.round(value * 1000) / 1000;
  }};
  const codecChecks = {{
    h264_baseline: document.createElement("video").canPlayType('video/mp4; codecs="avc1.42E01E"'),
    h264_main: document.createElement("video").canPlayType('video/mp4; codecs="avc1.4D401E"'),
    h264_high: document.createElement("video").canPlayType('video/mp4; codecs="avc1.640028"'),
    mp4_aac: document.createElement("audio").canPlayType('audio/mp4; codecs="mp4a.40.2"'),
    webm_vp9: document.createElement("video").canPlayType('video/webm; codecs="vp9"')
  }};

  const mse = typeof MediaSource !== "undefined" ? {{
    h264_baseline: MediaSource.isTypeSupported('video/mp4; codecs="avc1.42E01E, mp4a.40.2"'),
    h264_main: MediaSource.isTypeSupported('video/mp4; codecs="avc1.4D401E, mp4a.40.2"'),
    h264_high: MediaSource.isTypeSupported('video/mp4; codecs="avc1.640028, mp4a.40.2"'),
    webm_vp9: MediaSource.isTypeSupported('video/webm; codecs="vp9, opus"')
  }} : null;

  const mediaCapabilities = {{}};
  if (navigator.mediaCapabilities && typeof navigator.mediaCapabilities.decodingInfo === "function") {{
    for (const [label, config] of Object.entries({{
      h264_baseline: {{
        type: "file",
        video: {{
          contentType: 'video/mp4; codecs="avc1.42E01E"',
          width: 320,
          height: 180,
          bitrate: 250000,
          framerate: 30
        }},
        audio: {{
          contentType: 'audio/mp4; codecs="mp4a.40.2"',
          channels: "2",
          bitrate: 96000,
          samplerate: 48000
        }}
      }},
      h264_main: {{
        type: "file",
        video: {{
          contentType: 'video/mp4; codecs="avc1.4D401E"',
          width: 320,
          height: 180,
          bitrate: 250000,
          framerate: 30
        }},
        audio: {{
          contentType: 'audio/mp4; codecs="mp4a.40.2"',
          channels: "2",
          bitrate: 96000,
          samplerate: 48000
        }}
      }},
      vp9_webm: {{
        type: "file",
        video: {{
          contentType: 'video/webm; codecs="vp9"',
          width: 320,
          height: 180,
          bitrate: 250000,
          framerate: 30
        }}
      }}
    }})) {{
      try {{
        mediaCapabilities[label] = await navigator.mediaCapabilities.decodingInfo(config);
      }} catch (error) {{
        mediaCapabilities[label] = {{ error: String(error) }};
      }}
    }}
  }}

  const canvas = document.createElement("canvas");
  const gl = canvas.getContext("webgl") || canvas.getContext("experimental-webgl");
  let webgl = null;
  if (gl) {{
    const debugInfo = gl.getExtension("WEBGL_debug_renderer_info");
    webgl = {{
      vendor: gl.getParameter(gl.VENDOR),
      renderer: gl.getParameter(gl.RENDERER),
      version: gl.getParameter(gl.VERSION),
      shadingLanguageVersion: gl.getParameter(gl.SHADING_LANGUAGE_VERSION),
      unmaskedVendor: debugInfo ? gl.getParameter(debugInfo.UNMASKED_VENDOR_WEBGL) : null,
      unmaskedRenderer: debugInfo ? gl.getParameter(debugInfo.UNMASKED_RENDERER_WEBGL) : null
    }};
  }}

  const playback = await new Promise((resolve) => {{
    const video = document.createElement("video");
    video.muted = true;
    video.playsInline = true;
    video.preload = "auto";
    video.src = {json.dumps(mp4_url)};
    video.style.display = "none";
    document.body.appendChild(video);

    const result = {{
      src: video.src,
      events: [],
      playPromise: "not-called",
      mediaError: null
    }};
    const started = performance.now();
    let settled = false;

    const cleanup = () => {{
      video.pause();
      video.removeAttribute("src");
      video.load();
      video.remove();
    }};

    const finalize = (reason) => {{
      if (settled) return;
      settled = true;
      result.reason = reason;
      result.elapsedMs = Math.round(performance.now() - started);
      result.currentTime = round3(video.currentTime);
      result.duration = round3(video.duration);
      result.readyState = video.readyState;
      result.networkState = video.networkState;
      resolve(result);
      cleanup();
    }};

    const pushEvent = (name) => {{
      result.events.push({{
        name,
        currentTime: round3(video.currentTime),
        readyState: video.readyState,
        networkState: video.networkState
      }});
    }};

    for (const name of ["loadstart", "loadedmetadata", "loadeddata", "canplay", "canplaythrough", "play", "playing", "pause", "ended", "waiting", "stalled", "suspend", "error"]) {{
      video.addEventListener(name, () => {{
        pushEvent(name);
        if (name === "playing") {{
          setTimeout(() => finalize("playing"), 350);
        }} else if (name === "ended") {{
          finalize("ended");
        }} else if (name === "error") {{
          result.mediaError = video.error ? {{
            code: video.error.code,
            message: video.error.message || null
          }} : null;
          finalize("error");
        }}
      }});
    }}

    video.load();
    try {{
      const maybePromise = video.play();
      if (maybePromise && typeof maybePromise.then === "function") {{
        result.playPromise = "pending";
        maybePromise.then(() => {{
          result.playPromise = "resolved";
        }}).catch((error) => {{
          result.playPromise = "rejected";
          result.playError = String(error);
          finalize("play-rejected");
        }});
      }} else {{
        result.playPromise = "sync";
      }}
    }} catch (error) {{
      result.playPromise = "threw";
      result.playError = String(error);
      finalize("play-threw");
      return;
    }}

    setTimeout(() => finalize("timeout"), 5000);
  }});

  return {{
    href: location.href,
    readyState: document.readyState,
    userAgent: navigator.userAgent,
    platform: navigator.platform,
    language: navigator.language,
    languages: navigator.languages,
    webdriver: navigator.webdriver ?? null,
    userAgentData: navigator.userAgentData ? {{
      mobile: navigator.userAgentData.mobile,
      platform: navigator.userAgentData.platform,
      brands: navigator.userAgentData.brands
    }} : null,
    codecChecks,
    mediaSourceSupport: mse,
    mediaCapabilitiesSupported: !!navigator.mediaCapabilities,
    mediaCapabilities,
    playback,
    webgl
  }};
}})()
""".strip()
    response = send_request(
        socket_path,
        "evaluateJavaScript",
        browser_tab_id=browser_tab_id,
        payload={"script": script},
        timeout=20.0,
    )
    return extract_result_json(response["response"])


def run_mode(
    mode: str,
    *,
    app_bundle: Path,
    runtime_root: str,
    page_url: str,
    mp4_url: str,
    timeout_ms: int,
    workspace: Path,
) -> dict:
    mode_workspace = workspace / mode
    mode_workspace.mkdir(parents=True, exist_ok=True)
    app_support_root = mode_workspace / "app-support"
    home_dir = mode_workspace / "home"
    socket_path = str(app_support_root / "browser-control.sock")
    log_path = mode_workspace / "launch.log"

    configured_profile: str | None
    if mode == "external":
        profile_path = mode_workspace / "external-user-data" / "Profile 10"
        profile_path.mkdir(parents=True, exist_ok=True)
        configured_profile = str(profile_path)
    elif mode == "managed":
        configured_profile = None
    else:
        raise RuntimeError(f"Unsupported mode: {mode}")

    proc = launch_app(
        app_bundle,
        log_path,
        runtime_root=runtime_root,
        app_support_root=app_support_root,
        home_dir=home_dir,
        profile_path=configured_profile,
    )
    try:
        socket_ready = wait_for_socket_ready(socket_path, timeout_ms)
        pre_tab_debug = debug_status(socket_path)
        new_tab = send_request(
            socket_path,
            "newTab",
            payload={"url": page_url},
            timeout=max(30.0, (timeout_ms / 1000.0) + 5.0),
        )
        tab_summary = extract_result_json(new_tab["response"])
        browser_tab_id = tab_summary["id"]
        ready = wait_for_page_ready(socket_path, browser_tab_id, page_url, timeout_ms)
        post_tab_debug = debug_status(socket_path)
        probe = media_probe(socket_path, browser_tab_id, mp4_url)
        log_text = wait_for_log_substring(log_path, "[CEF] Initializing", timeout_ms)
        launch = parse_single_cef_init_log(log_text)
        listening_tcp = listening_tcp_sockets_for_pid(proc.pid)
    finally:
        terminate_process(proc)
        wait_for_socket_gone(socket_path, timeout_ms)

    return {
        "mode": mode,
        "workspace": str(mode_workspace),
        "home_dir": str(home_dir),
        "app_support_root": str(app_support_root),
        "socket_path": socket_path,
        "configured_profile_path": configured_profile,
        "socket_health": socket_ready["response"].get("ok") is True,
        "tab": {
            "id": browser_tab_id,
            "page_ready": ready,
        },
        "debug_status": {
            "before_new_tab": pre_tab_debug,
            "after_new_tab": post_tab_debug,
        },
        "launch": launch,
        "listening_tcp": listening_tcp,
        "probe": probe,
        "acceptance": {
            "debug_disabled_before_new_tab": pre_tab_debug.get("enabled") is False,
            "debug_disabled_after_new_tab": post_tab_debug.get("enabled") is False,
            "launch_remote_debug_port_zero": launch["remote_debug_port"] == 0,
            "remote_debug_listener_absent_on_main_process": not tcp_listener_present_for_port(
                listening_tcp,
                launch["remote_debug_port"],
            ),
            "h264_baseline_canplay": probe["codecChecks"].get("h264_baseline") not in ("", "no", None),
            "h264_playback_reached_playing": probe["playback"].get("reason") == "playing",
            "webdriver_is_not_true": probe.get("webdriver") is not True,
        },
        "artifacts": {
            "launch_log": str(log_path),
        },
    }


def main() -> int:
    args = parse_args()
    app_bundle = Path(os.path.expanduser(args.app)).resolve() if args.app else resolve_default_app().resolve()
    runtime_root = str(Path(os.path.expanduser(args.runtime_root)).resolve())

    if str(app_bundle) == "/Applications/GhoDex.app":
        raise SystemExit("Refusing to run against /Applications/GhoDex.app. Pass a dedicated build output instead.")
    if not app_bundle.exists():
        raise SystemExit(f"App bundle does not exist: {app_bundle}")
    if not Path(runtime_root).is_dir():
        raise SystemExit(f"Runtime root does not exist: {runtime_root}")

    modes = ["managed", "external"] if args.mode == "all" else [args.mode]
    workspace = Path(tempfile.mkdtemp(prefix="ghx-media-debug-", dir="/tmp"))

    with local_media_server() as server_info:
        results = [
            run_mode(
                mode,
                app_bundle=app_bundle,
                runtime_root=runtime_root,
                page_url=str(server_info["page_url"]),
                mp4_url=str(server_info["mp4_url"]),
                timeout_ms=args.page_timeout_ms,
                workspace=workspace,
            )
            for mode in modes
        ]

        artifact = {
            "app_bundle": str(app_bundle),
            "runtime_root": runtime_root,
            "workspace": str(workspace),
            "server": {
                "page_url": server_info["page_url"],
                "mp4_url": server_info["mp4_url"],
                "sample": server_info["sample"],
                "webroot": server_info["webroot"],
            },
            "results": results,
            "acceptance": {
                "all_debug_lanes_closed_by_default": all(
                    item["acceptance"]["debug_disabled_before_new_tab"]
                    and item["acceptance"]["debug_disabled_after_new_tab"]
                    and item["acceptance"]["launch_remote_debug_port_zero"]
                    for item in results
                ),
                "all_main_processes_keep_remote_debug_listener_absent": all(
                    item["acceptance"]["remote_debug_listener_absent_on_main_process"] for item in results
                ),
                "all_modes_hide_webdriver": all(
                    item["acceptance"]["webdriver_is_not_true"] for item in results
                ),
                "managed_h264_baseline_canplay": next(
                    (item["acceptance"]["h264_baseline_canplay"] for item in results if item["mode"] == "managed"),
                    None,
                ),
                "external_h264_baseline_canplay": next(
                    (item["acceptance"]["h264_baseline_canplay"] for item in results if item["mode"] == "external"),
                    None,
                ),
                "managed_h264_playback_reached_playing": next(
                    (item["acceptance"]["h264_playback_reached_playing"] for item in results if item["mode"] == "managed"),
                    None,
                ),
                "external_h264_playback_reached_playing": next(
                    (item["acceptance"]["h264_playback_reached_playing"] for item in results if item["mode"] == "external"),
                    None,
                ),
            },
            "notes": [
                "Each lane runs with isolated HOME and GHODEX_BROWSER_APP_SUPPORT_ROOT so it does not overlap with the user's live app state.",
                "The probe uses a local ffmpeg-generated H.264/AAC MP4 plus browser.tab.v1 evaluateJavaScript to collect codec, mediaCapabilities, WebGL, webdriver, and playback results.",
                "The debug proof combines getDebugStatus, the CEF initialization log line, and a per-pid listening TCP snapshot for the main app process.",
            ],
        }

    output_path = Path(args.output)
    output_path.write_text(json.dumps(artifact, indent=2), encoding="utf-8")
    print(json.dumps(artifact, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
