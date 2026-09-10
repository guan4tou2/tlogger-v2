#!/usr/bin/env python3
"""Drive an interactive zsh through a real pty and save what the screen saw.

The hooks tlogger relies on only fire in an interactive shell attached to a
terminal, so tests cannot use `zsh -c`: with a pipe on stdout every command
already looks redirected and the interesting behaviour disappears.

usage: pty_driver.py <HOME> <transcript> [command ...]
       a command of __CTRLZ__ / __CTRLC__ / __ESC__ sends that key instead.
"""
import fcntl
import os
import pty
import select
import struct
import sys
import termios
import time

KEYS = {"__CTRLZ__": b"\x1a", "__CTRLC__": b"\x03", "__ESC__": b"\x1b"}
SETTLE = float(os.environ.get("TLOGGER_TEST_SETTLE", "2"))
ROWS, COLS = 40, 120


def main() -> int:
    home, transcript, *commands = sys.argv[1:]
    pid, fd = pty.fork()
    if pid == 0:
        os.environ["HOME"] = home
        os.environ["TERM"] = "xterm"
        os.chdir(home)
        os.execvp("zsh", ["zsh", "-i"])

    # A pty starts out 0x0. Full-screen programs and prompt libraries ask the
    # terminal how big it is and stall or misdraw when the answer is nothing,
    # which looks exactly like the program hanging.
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, COLS, 0, 0))

    seen = bytearray()

    def drain(seconds: float) -> None:
        deadline = time.time() + seconds
        while time.time() < deadline:
            ready, _, _ = select.select([fd], [], [], 0.2)
            if fd in ready:
                try:
                    chunk = os.read(fd, 65536)
                except OSError:
                    return
                if not chunk:
                    return
                seen.extend(chunk)

    drain(SETTLE)
    for command in commands:
        os.write(fd, KEYS.get(command, (command + "\n").encode()))
        drain(SETTLE)
    drain(1)

    with open(transcript, "wb") as handle:
        handle.write(bytes(seen))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
