#!/usr/bin/env python3
"""Synthetic channel-kill test for the QGA-channel-loss failure class (#220).

A deaf virtio-serial channel and a stalled installer look identical from the
harness: the guest stops answering and the drive-state file stops changing.
They have opposite causes, and until the channel is asked directly, a run that
lost the channel reports a verdict on a product it can no longer observe —
el10-gnome-win11pro in run 32556250889 spent its full 30-minute drive deadline
doing exactly that.

These tests kill a REAL AF_UNIX channel underneath the client rather than
faking the client's own methods, because the two things #220 turns on both
live below the protocol: whether a reopen drains what a killed client left
behind, and whether a socket that will not open is reported as a TRANSPORT
failure or masquerades as a guest exit code.

Run: python3 tests/unit/test_qga_reconnect.py
"""

import importlib.util
import json
import os
import pathlib
import socket
import sys
import tempfile
import threading
import time

HERE = pathlib.Path(__file__).resolve().parent
QGA = HERE.parent / "e2e" / "qga.py"

spec = importlib.util.spec_from_file_location("qga", QGA)
qga = importlib.util.module_from_spec(spec)
spec.loader.exec_module(qga)


class FakeQGA(threading.Thread):
    """A real Unix socket that speaks just enough QGA to be killed credibly.

    `script` gives the behaviour of each accepted connection in turn; the last
    entry repeats forever, so ["deaf", "deaf", "healthy"] is a channel that
    comes back on the third reopen.

      healthy  answers guest-sync-delimited and guest-ping
      deaf     accepts and answers NOTHING (the #220 signature: the socket is
               there, the agent behind it is not)
      poison   writes a dead client's leftovers — including a half line with
               no terminator — the instant it accepts, then serves normally
    """

    daemon = True

    def __init__(self, path, script):
        super().__init__()
        self.path = path
        self.script = list(script)
        self.connections = 0
        self.stop = threading.Event()
        self.listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.listener.bind(path)
        self.listener.listen(8)
        self.listener.settimeout(0.2)

    def behaviour_for(self, index):
        return self.script[min(index, len(self.script) - 1)]

    def run(self):
        while not self.stop.is_set():
            try:
                conn, _ = self.listener.accept()
            except socket.timeout:
                continue
            except OSError:
                return
            behaviour = self.behaviour_for(self.connections)
            self.connections += 1
            threading.Thread(
                target=self._serve, args=(conn, behaviour), daemon=True
            ).start()

    def shutdown(self):
        self.stop.set()
        try:
            self.listener.close()
        except OSError:
            pass
        self.join(timeout=2)
        try:
            os.unlink(self.path)
        except OSError:
            pass

    def _serve(self, conn, behaviour):
        try:
            if behaviour == "poison":
                # Exactly what a client killed mid-request leaves behind: a
                # complete reply nobody is waiting for, then a truncated one.
                conn.sendall(
                    b'{"return": {"pid": 4321}}\n'
                    b'{"return": "half a line from a client that was killed'
                )
                time.sleep(0.05)
            if behaviour == "deaf":
                self.stop.wait(5)
                return
            stream = conn.makefile("rwb")
            while not self.stop.is_set():
                line = stream.readline()
                if not line:
                    return
                delimited = line[0:1] == b"\xff"
                message = json.loads(line[1:] if delimited else line)
                execute = message.get("execute")
                if execute == "guest-sync-delimited":
                    reply = {"return": message["arguments"]["id"]}
                    stream.write(b"\xff" + json.dumps(reply).encode() + b"\n")
                elif execute == "guest-ping":
                    stream.write(json.dumps({"return": {}}).encode() + b"\n")
                else:
                    stream.write(
                        json.dumps(
                            {"error": {"class": "CommandNotFound", "desc": execute}}
                        ).encode()
                        + b"\n"
                    )
                stream.flush()
        except (OSError, ValueError):
            return
        finally:
            try:
                conn.close()
            except OSError:
                pass


def _sock_path(tmp, name):
    return os.path.join(tmp, name)


def _quiet(_message):
    """reconnect() logs to stderr by default; the tests do not need the noise."""


def main():
    failures = []
    checks = 0

    def check(ok, message):
        nonlocal checks
        checks += 1
        if not ok:
            failures.append(message)

    tmp = tempfile.mkdtemp(prefix="qga-channel-kill-")

    # 1. A live channel is recovered on the FIRST attempt — the cycle must not
    #    charge a healthy channel for the settle delays it budgeted.
    path = _sock_path(tmp, "healthy.sock")
    server = FakeQGA(path, ["healthy"])
    server.start()
    try:
        ok = qga.reconnect(path, attempts=3, settle=5.0, timeout=2.0, log=_quiet)
        check(ok, "healthy channel: reconnect() did not recover it")
        check(
            server.connections == 1,
            "healthy channel: took %d connections, expected 1" % server.connections,
        )
    finally:
        server.shutdown()

    # 2. THE CHANNEL KILL. A socket that accepts and then answers nothing is
    #    the #220 signature. reconnect() must give up inside its budget rather
    #    than hand the caller another half hour of waiting.
    path = _sock_path(tmp, "deaf.sock")
    server = FakeQGA(path, ["deaf"])
    server.start()
    try:
        started = time.monotonic()
        ok = qga.reconnect(path, attempts=3, settle=0.0, timeout=0.5, log=_quiet)
        elapsed = time.monotonic() - started
        check(not ok, "killed channel: reconnect() claimed a recovery it never got")
        check(
            elapsed < 15,
            "killed channel: reconnect() took %.1fs — it is not bounded" % elapsed,
        )
        check(
            server.connections == 3,
            "killed channel: %d attempts, expected the 3 it was given"
            % server.connections,
        )
    finally:
        server.shutdown()

    # 3. A channel that comes back WITHIN the budget is recovered, and the run
    #    continues. This is the case that must not become a red: one bounded
    #    cycle, then the install goes on.
    path = _sock_path(tmp, "revives.sock")
    server = FakeQGA(path, ["deaf", "deaf", "healthy"])
    server.start()
    try:
        ok = qga.reconnect(path, attempts=3, settle=0.0, timeout=0.5, log=_quiet)
        check(ok, "revived channel: reconnect() gave up on a channel that came back")
    finally:
        server.shutdown()

    # 4. Socket poisoning: the single-client socket hands the next connection
    #    whatever the killed client never read. Without a drain the leftovers
    #    are joined onto the head of the sync reply and the reopen is useless.
    path = _sock_path(tmp, "poisoned.sock")
    server = FakeQGA(path, ["poison"])
    server.start()
    try:
        agent = None
        drained = -1
        pinged = False
        try:
            agent = qga.GuestAgent(path, timeout=2.0, drain_grace=0.5)
            drained = agent.drained
            agent.request("guest-ping")
            pinged = True
        except (OSError, RuntimeError, ValueError) as error:
            failures.append("poisoned socket: reopen failed (%s)" % error)
        finally:
            if agent is not None:
                agent.close()
        check(pinged, "poisoned socket: the reopened channel never answered ping")
        check(
            drained > 0,
            "poisoned socket: %d bytes drained — the sync only got lucky, and "
            "the leftovers are still ahead of the next reply" % drained,
        )
    finally:
        server.shutdown()

    # 5. THE MASQUERADE. A socket that will not open is a transport failure. It
    #    used to exit 1, which is indistinguishable from a guest command that
    #    ran and returned 1 — so qga_call_retry would not retry it (#40 forbids
    #    replaying guest exit codes) and callers read a dead channel as a real,
    #    guest-side failure.
    missing = _sock_path(tmp, "not-here.sock")
    argv = sys.argv
    try:
        sys.argv = ["qga.py", "--socket", missing, "ping"]
        rc = qga.main()
        check(
            rc == qga.TRANSPORT_EXIT,
            "dead socket: qga.py ping exited %r, expected TRANSPORT_EXIT (%d)"
            % (rc, qga.TRANSPORT_EXIT),
        )
    finally:
        sys.argv = argv

    # 6. And the CLI the harness calls reports a spent budget the same way, so
    #    a failed reconnect is retryable transport, never a product verdict.
    path = _sock_path(tmp, "deaf-cli.sock")
    server = FakeQGA(path, ["deaf"])
    server.start()
    try:
        sys.argv = [
            "qga.py", "--socket", path, "reconnect",
            "--attempts", "2", "--settle", "0", "--timeout", "0.5",
        ]
        rc = qga.main()
        check(
            rc == qga.TRANSPORT_EXIT,
            "reconnect CLI: exited %r on a deaf channel, expected TRANSPORT_EXIT "
            "(%d)" % (rc, qga.TRANSPORT_EXIT),
        )
    finally:
        sys.argv = argv
        server.shutdown()

    try:
        os.rmdir(tmp)
    except OSError:
        pass

    for failure in failures:
        print("FAIL: %s" % failure)
    print("%s (%d checks)" % ("FAIL" if failures else "PASS", checks))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
