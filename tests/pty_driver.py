#!/usr/bin/env python3
"""Drive an interactive zsh through a real pty and save what the screen saw.

The hooks tlogger relies on only fire in an interactive shell attached to a
terminal, so tests cannot use `zsh -c`: with a pipe on stdout every command
already looks redirected and the interesting behaviour disappears.

usage: pty_driver.py <HOME> <transcript> [command ...]
       a command of __CTRLZ__ / __CTRLC__ / __ESC__ sends that key instead.

Between commands it waits for output to go idle rather than for a fixed
time: a fixed wait is either too short for a slow command (rm -rf, the first
command after a cold start) and drops its output, or needlessly slow for
everything else. TLOGGER_TEST_SETTLE sets the idle gap and the ceiling.
"""
import fcntl
import os
import pty
import select
import struct
import sys
import termios
import time

KEYS = {
    "__CTRLZ__": b"\x1a",
    "__CTRLC__": b"\x03",
    "__CTRLD__": b"\x04",
    "__ESC__": b"\x1b",
}
# Idle gap: how long output must be silent before the next command is sent.
IDLE = float(os.environ.get("TLOGGER_TEST_SETTLE", "0.6"))
# Hard ceiling per command, so a genuinely stuck program cannot hang the run.
CEILING = max(8.0, IDLE * 6)
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

    def drain_until_idle() -> None:
        # Read until output has been silent for IDLE seconds, or CEILING total.
        # A command may be slow to produce its first byte (a cold start, rm on
        # a large tree); until something has arrived, wait GRACE rather than
        # IDLE, so an empty transcript is a real hang and not just impatience.
        grace = max(2.0, IDLE * 3)
        hard_stop = time.time() + CEILING
        last_data = time.time()
        saw_data = False
        while time.time() < hard_stop:
            ready, _, _ = select.select([fd], [], [], 0.1)
            if fd in ready:
                try:
                    chunk = os.read(fd, 65536)
                except OSError:
                    return
                if not chunk:
                    return
                seen.extend(chunk)
                last_data = time.time()
                saw_data = True
            else:
                quiet = time.time() - last_data
                if saw_data and quiet >= IDLE:
                    return
                if not saw_data and quiet >= grace:
                    return

    drain_until_idle()
    for command in commands:
        os.write(fd, KEYS.get(command, (command + "\n").encode()))
        drain_until_idle()

    with open(transcript, "wb") as handle:
        handle.write(bytes(seen))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
