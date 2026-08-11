#!/usr/bin/env python3
"""Run a network command with bounded retries and optional DNS probes."""

from __future__ import annotations

import argparse
import os
import signal
import subprocess
import sys
import time
from collections.abc import Sequence


TIMEOUT_EXIT_CODE = 124
DNS_FAILURE_EXIT_CODE = 68
DNS_PROBE_TIMEOUT_SECONDS = 10
TERMINATE_GRACE_SECONDS = 10
DNS_PROBE_SCRIPT = """
import socket
import sys

answers = socket.getaddrinfo(sys.argv[1], 443, type=socket.SOCK_STREAM)
print(", ".join(sorted({answer[4][0] for answer in answers})))
"""


def positive_int(value: str) -> int:
    parsed = int(value)
    if parsed < 1:
        raise argparse.ArgumentTypeError("must be a positive integer")
    return parsed


def nonnegative_int(value: str) -> int:
    parsed = int(value)
    if parsed < 0:
        raise argparse.ArgumentTypeError("must be a nonnegative integer")
    return parsed


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--attempts", type=positive_int, default=1)
    parser.add_argument("--attempt-timeout-seconds", type=positive_int, required=True)
    parser.add_argument("--delay-seconds", type=nonnegative_int, default=0)
    parser.add_argument("--probe-host", action="append", default=[])
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.command[:1] == ["--"]:
        args.command = args.command[1:]
    if not args.command:
        parser.error("a command is required after --")
    return args


def probe_dns(hosts: Sequence[str]) -> bool:
    resolved = True
    for host in hosts:
        try:
            result = subprocess.run(
                [sys.executable, "-c", DNS_PROBE_SCRIPT, host],
                capture_output=True,
                check=False,
                text=True,
                timeout=DNS_PROBE_TIMEOUT_SECONDS,
            )
        except subprocess.TimeoutExpired:
            print(
                f"::warning::DNS resolution for {host} exceeded "
                f"{DNS_PROBE_TIMEOUT_SECONDS} seconds.",
                file=sys.stderr,
                flush=True,
            )
            resolved = False
            continue

        if result.returncode != 0:
            error_lines = result.stderr.strip().splitlines()
            detail = (
                error_lines[-1]
                if error_lines
                else f"resolver exited with {result.returncode}"
            )
            print(
                f"::warning::DNS resolution failed for {host}: {detail}",
                file=sys.stderr,
                flush=True,
            )
            resolved = False
            continue

        print(f"DNS probe for {host}: {result.stdout.strip()}", flush=True)
    return resolved


def terminate_process(process: subprocess.Popen[bytes]) -> None:
    if process.poll() is not None:
        return

    try:
        if os.name == "posix":
            os.killpg(process.pid, signal.SIGTERM)
        else:
            process.terminate()
    except ProcessLookupError:
        process.wait()
        return

    try:
        process.wait(timeout=TERMINATE_GRACE_SECONDS)
        return
    except subprocess.TimeoutExpired:
        pass

    if os.name == "posix":
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    else:
        process.kill()
    process.wait()


def run_command(command: Sequence[str], timeout_seconds: int) -> int:
    popen_options: dict[str, object] = {}
    if os.name == "posix":
        popen_options["start_new_session"] = True

    process = subprocess.Popen(command, **popen_options)
    try:
        return process.wait(timeout=timeout_seconds)
    except subprocess.TimeoutExpired:
        print(
            f"::warning::Network command exceeded {timeout_seconds} seconds; terminating it.",
            file=sys.stderr,
            flush=True,
        )
        terminate_process(process)
        return TIMEOUT_EXIT_CODE


def main() -> None:
    args = parse_args()
    last_status = 1

    for attempt in range(1, args.attempts + 1):
        print(f"Network command attempt {attempt}/{args.attempts}.", flush=True)
        if probe_dns(args.probe_host):
            last_status = run_command(args.command, args.attempt_timeout_seconds)
        else:
            last_status = DNS_FAILURE_EXIT_CODE

        if last_status == 0:
            return

        print(
            f"::warning::Network command attempt {attempt}/{args.attempts} "
            f"failed with status {last_status}.",
            file=sys.stderr,
            flush=True,
        )
        if attempt < args.attempts:
            delay = args.delay_seconds * attempt
            print(f"Retrying in {delay} seconds.", flush=True)
            time.sleep(delay)

    if not 1 <= last_status <= 255:
        last_status = 1
    raise SystemExit(last_status)


if __name__ == "__main__":
    main()
