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
import random
import socket
import sys
import time

# Reserved exit code for transport/QGA protocol errors, distinct from guest
# process exit codes so callers can retry connection failures without replaying
# side-effecting guest commands (see #40).
TRANSPORT_EXIT = 42

SOCKET = "/run/shm/qga.sock"


class GuestAgent:
    def __init__(self, path=SOCKET, timeout=60.0, drain_grace=0.0):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.timeout = timeout
        self.sock.settimeout(timeout)
        self.sock.connect(path)
        # Drain BEFORE makefile(): the bytes a dead client left behind are raw
        # socket data, and once a buffered reader has joined them onto the head
        # of our first real response there is no un-joining them.
        self.drained = self._drain(drain_grace)
        self.file = self.sock.makefile("rwb")
        self._sync()

    def _drain(self, grace=0.0):
        """Discard whatever a previous client left in the channel.

        The QGA virtio-serial socket takes ONE client at a time, so a client
        that was KILLED mid-request (our `timeout` wrapper does exactly that on
        124) leaves its reply queued: the next connection reads that reply as
        the answer to a question it never asked, and every subsequent response
        is off by one — the channel is open and useless. guest-sync-delimited
        re-anchors the stream, but only once the backlog ahead of it is gone.

        `grace` is a bounded blocking window: 0 means "take only what has
        already arrived" (the hot path, no added latency), and the recovery
        path in reconnect() pays a fraction of a second to also catch bytes
        still in flight. Bounded either way — a channel that streams forever
        must not turn a drain into the hang it exists to prevent.
        """
        discarded = 0
        deadline = time.monotonic() + max(grace, 0.0) + 1.0
        self.sock.settimeout(grace if grace > 0 else 0.0)
        try:
            while time.monotonic() < deadline and discarded < 4 * 1024 * 1024:
                try:
                    chunk = self.sock.recv(65536)
                except (BlockingIOError, socket.timeout):
                    break
                except OSError:
                    break
                if not chunk:
                    break
                discarded += len(chunk)
        finally:
            self.sock.settimeout(self.timeout)
        return discarded

    def _sync(self):
        """Synchronize with QGA using guest-sync-delimited.

        Generates a random 64-bit ID, sends the 0xFF-delimited sync command,
        and discards all input until the matching response is observed.
        This ensures stale data from a previous timed-out client is never
        attributed to this connection's requests (#41).
        """
        sync_id = random.randint(0, 2**63 - 1)
        cmd = json.dumps(
            {"execute": "guest-sync-delimited", "arguments": {"id": sync_id}}
        )
        self.file.write(b"\xff" + cmd.encode("utf-8") + b"\n")
        self.file.flush()
        while True:
            raw = self.file.readline()
            if not raw:
                raise RuntimeError("QGA socket closed during sync")
            if raw and raw[0:1] == b"\xff":
                try:
                    response = json.loads(raw[1:])
                except (json.JSONDecodeError, ValueError):
                    continue
                if response.get("return") == sync_id:
                    return

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

    def exec(self, path, args, exec_timeout=None):
        if exec_timeout is None:
            exec_timeout = self.sock.gettimeout() or 60.0
        result = self.request(
            "guest-exec",
            {
                "path": path,
                "arg": args,
                "capture-output": True,
            },
        )
        pid = result["pid"]
        deadline = time.monotonic() + exec_timeout
        while True:
            if time.monotonic() >= deadline:
                raise RuntimeError(
                    "guest-exec timed out after %.0fs (pid=%d): process has not exited"
                    % (exec_timeout, pid)
                )
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


def reconnect(path=SOCKET, attempts=3, settle=3.0, timeout=10.0, log=None):
    """One bounded reconnect cycle against a channel that stopped answering.

    Returns True as soon as a freshly opened connection gets a guest-ping back,
    False once the attempt budget is spent.  Each attempt is a full cycle:
    open, drain what the previous client left, re-anchor with a 0xFF-delimited
    sync, ping.

    BOUNDED is the whole point.  A deaf virtio-serial channel does not heal by
    being asked again for half an hour — el10-gnome-win11pro in run
    32556250889 waited out its full 30-minute drive deadline and then reported
    the product as broken on evidence it did not have (#220).  Either a small
    number of clean reopens gets the channel back, or the caller must classify
    the run `qga-channel-lost` and let the retry gate re-dispatch it.
    """
    def emit(message):
        (log or (lambda m: print("QGA reconnect: %s" % m, file=sys.stderr)))(message)

    for attempt in range(1, attempts + 1):
        agent = None
        try:
            agent = GuestAgent(path, timeout=timeout, drain_grace=0.5)
            agent.request("guest-ping")
            emit(
                "attempt %d/%d: channel answered guest-ping "
                "(discarded %d stale bytes)" % (attempt, attempts, agent.drained)
            )
            return True
        except (OSError, RuntimeError, ValueError) as error:
            emit("attempt %d/%d: %s" % (attempt, attempts, error))
        finally:
            if agent is not None:
                try:
                    agent.close()
                except OSError:
                    pass
        if attempt < attempts:
            time.sleep(settle)
    return False


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
    recon = sub.add_parser("reconnect")
    recon.add_argument("--attempts", type=int, default=3)
    recon.add_argument("--settle", type=float, default=3.0)
    recon.add_argument("--timeout", type=float, default=10.0)
    args = parser.parse_args()

    if args.command == "reconnect":
        if reconnect(
            args.socket,
            attempts=args.attempts,
            settle=args.settle,
            timeout=args.timeout,
        ):
            return 0
        print(
            "QGA: channel still deaf after %d reconnect attempts — qga-channel-lost"
            % args.attempts,
            file=sys.stderr,
        )
        return TRANSPORT_EXIT

    # A socket that will not open is a TRANSPORT failure, and it used to exit
    # 1: the connect() sat OUTSIDE this try, so ENOENT/ECONNREFUSED on a dead
    # channel raised a bare traceback.  Exit 1 is indistinguishable from a
    # guest command that ran and returned 1, so qga_call_retry refused to retry
    # it (#40 forbids replaying guest exit codes) and every caller read a dead
    # socket as a real, guest-side failure — the masquerade #220 is about.
    try:
        agent = GuestAgent(args.socket)
    except (OSError, RuntimeError, ValueError) as error:
        print(f"QGA: cannot open {args.socket}: {error}", file=sys.stderr)
        return TRANSPORT_EXIT
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
        return TRANSPORT_EXIT
    finally:
        try:
            agent.close()
        except OSError:
            pass


if __name__ == "__main__":
    raise SystemExit(main())
