#!/usr/bin/env python3
import argparse
import json
import socket
import subprocess
import sys
import time
from statistics import mean


def send_gateway_command(host: str, port: int, request_id: str, command: str) -> dict:
    payload = json.dumps({"request_id": request_id, "command": command}).encode("utf-8")
    with socket.create_connection((host, port), timeout=3.0) as sock:
        sock.sendall(payload)
        sock.shutdown(socket.SHUT_WR)
        chunks = []
        while True:
            data = sock.recv(65536)
            if not data:
                break
            chunks.append(data)
    raw = b"".join(chunks).decode("utf-8")
    return json.loads(raw)


def sample_cpu_percent(pid: int) -> float:
    proc = subprocess.run(
        ["ps", "-p", str(pid), "-o", "%cpu="],
        check=True,
        capture_output=True,
        text=True,
    )
    return float(proc.stdout.strip())


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Capture a coarse live CPU window and gateway.metrics snapshot for control acceptance."
    )
    parser.add_argument("--pid", type=int, required=True, help="PID of the live GhoDex/Ghostty process")
    parser.add_argument("--host", default="127.0.0.1", help="Gateway listen host")
    parser.add_argument("--port", type=int, required=True, help="Gateway listen port")
    parser.add_argument("--duration", type=float, default=10.0, help="Observation window in seconds")
    parser.add_argument("--interval", type=float, default=1.0, help="CPU sample interval in seconds")
    parser.add_argument("--label", default="live-smoke", help="Scenario label")
    parser.add_argument("--skip-reset", action="store_true", help="Do not send gateway.metrics.reset first")
    parser.add_argument("--output", help="Optional JSON output path")
    args = parser.parse_args()

    if not args.skip_reset:
        send_gateway_command(args.host, args.port, "req-metrics-reset", "gateway.metrics.reset")

    samples = []
    started_at = time.time()
    while True:
        samples.append(sample_cpu_percent(args.pid))
        if time.time() - started_at >= args.duration:
            break
        time.sleep(args.interval)

    metrics = send_gateway_command(args.host, args.port, "req-metrics", "gateway.metrics")
    result = {
        "label": args.label,
        "pid": args.pid,
        "host": args.host,
        "port": args.port,
        "duration_s": args.duration,
        "interval_s": args.interval,
        "cpu_samples_percent": samples,
        "cpu_min_percent": min(samples) if samples else 0.0,
        "cpu_max_percent": max(samples) if samples else 0.0,
        "cpu_avg_percent": mean(samples) if samples else 0.0,
        "metrics_envelope": metrics,
    }

    output = json.dumps(result, ensure_ascii=True, indent=2)
    if args.output:
        with open(args.output, "w", encoding="utf-8") as f:
            f.write(output)
            f.write("\n")
    else:
        sys.stdout.write(output)
        sys.stdout.write("\n")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
