#!/usr/bin/env python3
"""Small QEMU Guest Agent client used by the Windows E2E runner.

QGA speaks newline-delimited JSON on its virtio-serial socket.  This client
intentionally uses only the standard library so it can run inside Dockur's
container without adding another dependency.
"""

import argparse
import base64
import json
import os
import socket
import sys
import time

SOCKET = "/run/shm/qga.sock"


class GuestAgent:
    def __init__(self, path=SOCKET, timeout=60.0):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(timeout)
        self.sock.connect(path)
        self.file = self.sock.makefile("rwb")

    def close(self):
        try:
            self.file.close()
        finally:
            self.sock.close()

    def request(self, execute, arguments=None):
        message = {"execute": execute}
        if arguments is not None:
            message["arguments"] = arguments
        self.file.write((json.dumps(message) + "\n").encode("utf-8"))
        self.file.flush()
        while True:
            line = self.file.readline()
            if not line:
                raise RuntimeError("QGA socket closed")
            response = json.loads(line)
            # QGA can emit asynchronous events; the command response has a
            # return or error member and is the only response callers need.
            if "return" in response:
                return response["return"]
            if "error" in response:
                error = response["error"]
                raise RuntimeError(
                    f"{error.get('class', 'QGA error')}: {error.get('desc', error)}"
                )

    def exec(self, path, args):
        result = self.request(
            "guest-exec",
            {
                "path": path,
                "arg": args,
                "capture-output": True,
            },
        )
        pid = result["pid"]
        while True:
            status = self.request("guest-exec-status", {"pid": pid})
            if status.get("exited"):
                stdout = base64.b64decode(status.get("out-data", ""))
                stderr = base64.b64decode(status.get("err-data", ""))
                return status.get("exitcode", 1), stdout, stderr
            time.sleep(0.25)

    def read_file(self, path):
        handle = self.request("guest-file-open", {"path": path, "mode": "r"})
        chunks = []
        try:
            while True:
                result = self.request(
                    "guest-file-read", {"handle": handle, "count": 1024 * 1024}
                )
                chunks.append(base64.b64decode(result.get("buf-b64", "")))
                if result.get("eof"):
                    break
        finally:
            self.request("guest-file-close", {"handle": handle})
        return b"".join(chunks)

    def write_file(self, local_path, guest_path):
        """Copy a local file to the guest through QGA in bounded chunks."""
        handle = self.request("guest-file-open", {"path": guest_path, "mode": "w"})
        written_total = 0
        try:
            with open(local_path, "rb") as source:
                while True:
                    chunk = source.read(256 * 1024)
                    if not chunk:
                        break
                    # guest-file-write returns the number of bytes ACTUALLY
                    # written, which may be less than the buffer submitted.
                    # Ignoring it silently truncated boot-critical payloads
                    # (kernel, initramfs, EFI binaries) while reporting success,
                    # so the resulting boot failure surfaced far from its cause
                    # (#42). Write the remainder until the chunk is consumed,
                    # and fail loudly on zero/invalid progress rather than
                    # spinning or advancing past a hole.
                    offset = 0
                    while offset < len(chunk):
                        res = self.request(
                            "guest-file-write",
                            {
                                "handle": handle,
                                "buf-b64": base64.b64encode(chunk[offset:]).decode("ascii"),
                            },
                        )
                        count = (res or {}).get("count")
                        if not isinstance(count, int) or count <= 0:
                            raise RuntimeError(
                                "guest-file-write made no progress on %s at byte %d "
                                "(count=%r); guest file is incomplete"
                                % (guest_path, written_total + offset, count)
                            )
                        offset += count
                        written_total += count
        finally:
            # Flush before close so the guest cannot report success on data
            # still buffered, and let close errors propagate.
            try:
                self.request("guest-file-flush", {"handle": handle})
            except Exception:
                pass
            self.request("guest-file-close", {"handle": handle})

        expected = os.path.getsize(local_path)
        if written_total != expected:
            raise RuntimeError(
                "short write to %s: wrote %d of %d bytes"
                % (guest_path, written_total, expected)
            )
        return written_total


def powershell(agent, command):
    return agent.exec(
        r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe",
        ["-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", command],
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--socket", default=SOCKET)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("ping")
    sub.add_parser("info")
    sub.add_parser("freeze")
    sub.add_parser("thaw")
    ps = sub.add_parser("powershell")
    ps.add_argument("script")
    execute = sub.add_parser("exec")
    execute.add_argument("path")
    execute.add_argument("args", nargs=argparse.REMAINDER)
    read = sub.add_parser("read")
    read.add_argument("path")
    write = sub.add_parser("write")
    write.add_argument("local_path")
    write.add_argument("guest_path")
    args = parser.parse_args()

    agent = GuestAgent(args.socket)
    try:
        if args.command == "ping":
            agent.request("guest-ping")
            return 0
        if args.command == "info":
            print(json.dumps(agent.request("guest-info"), sort_keys=True))
            return 0
        if args.command == "freeze":
            print(agent.request("guest-fsfreeze-freeze"))
            return 0
        if args.command == "thaw":
            print(agent.request("guest-fsfreeze-thaw"))
            return 0
        if args.command == "read":
            sys.stdout.buffer.write(agent.read_file(args.path))
            return 0
        if args.command == "write":
            agent.write_file(args.local_path, args.guest_path)
            return 0
        if args.command == "powershell":
            code, stdout, stderr = powershell(agent, args.script)
            sys.stdout.buffer.write(stdout)
            sys.stderr.buffer.write(stderr)
            return code
        if args.command == "exec":
            code, stdout, stderr = agent.exec(args.path, args.args)
            sys.stdout.buffer.write(stdout)
            sys.stderr.buffer.write(stderr)
            return code
        raise AssertionError(args.command)
    except (OSError, RuntimeError, ValueError) as error:
        print(f"QGA: {error}", file=sys.stderr)
        return 1
    finally:
        agent.close()


if __name__ == "__main__":
    raise SystemExit(main())
