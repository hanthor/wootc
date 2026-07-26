#!/usr/bin/env python3
"""Guard the QGA guest-file write path against SHORT and ZERO-byte writes (#42).

`guest-file-write` returns the number of bytes ACTUALLY written, which the
protocol allows to be smaller than the buffer submitted. The original
write_file() ignored that count and advanced to the next local chunk, silently
truncating boot-critical payloads (kernel, initramfs, EFI binaries) while
reporting success — so the resulting boot failure surfaced far from its cause.

Run: python3 tests/unit/test_qga_write.py
"""

import importlib.util
import os
import pathlib
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
QGA = HERE.parent / "e2e" / "qga.py"

spec = importlib.util.spec_from_file_location("qga", QGA)
qga = importlib.util.module_from_spec(spec)
spec.loader.exec_module(qga)


class FakeAgent(qga.GuestAgent):
    """A GuestAgent that never touches a socket; it fakes guest-file-*."""

    def __init__(self, behaviour):
        self.behaviour = behaviour        # "short" | "zero" | "full"
        self.written = bytearray()
        self.flushed = False
        self.closed = False

    def request(self, execute, arguments=None):
        if execute == "guest-file-open":
            return 1
        if execute == "guest-file-write":
            import base64
            buf = base64.b64decode(arguments["buf-b64"])
            if self.behaviour == "zero":
                return {"count": 0}
            if self.behaviour == "short":
                # Accept only the first half of whatever is offered, so a
                # correct implementation must loop to finish the chunk.
                n = max(1, len(buf) // 2)
            else:
                n = len(buf)
            self.written.extend(buf[:n])
            return {"count": n}
        if execute == "guest-file-flush":
            self.flushed = True
            return {}
        if execute == "guest-file-close":
            self.closed = True
            return {}
        raise AssertionError("unexpected request: %s" % execute)


def _payload(size):
    fd, path = tempfile.mkstemp()
    with os.fdopen(fd, "wb") as fh:
        fh.write(bytes(range(256)) * (size // 256 + 1))
    return path


def main():
    failures = []
    path = _payload(700 * 1024)          # spans multiple 256 KiB chunks
    expected = os.path.getsize(path)

    # 1. A guest that accepts only half of each buffer must still receive the
    #    WHOLE file, byte-for-byte.
    agent = FakeAgent("short")
    agent.write_file(path, r"C:\OEM\payload.bin")
    if bytes(agent.written) != open(path, "rb").read():
        failures.append("short writes: guest content does not match the source")
    if len(agent.written) != expected:
        failures.append(
            "short writes: wrote %d of %d bytes" % (len(agent.written), expected)
        )
    if not agent.closed:
        failures.append("short writes: guest handle was not closed")

    # 2. A guest making NO progress must raise, not spin and not report success.
    agent = FakeAgent("zero")
    try:
        agent.write_file(path, r"C:\OEM\payload.bin")
        failures.append("zero-byte writes: no error raised (silent truncation)")
    except RuntimeError:
        pass
    if not agent.closed:
        failures.append("zero-byte writes: guest handle was not closed on error")

    # 3. The happy path still transfers everything and reports the byte count.
    agent = FakeAgent("full")
    n = agent.write_file(path, r"C:\OEM\payload.bin")
    if n != expected or bytes(agent.written) != open(path, "rb").read():
        failures.append("full writes: transfer incomplete")

    os.unlink(path)
    for f in failures:
        print("FAIL: %s" % f)
    print("%s (%d checks)" % ("FAIL" if failures else "PASS", 3))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
