#!/usr/bin/env python3
"""Real-terminal colour and job-control regression checks (Linux, pexpect).

Installs only into a temporary directory. Does not source the user's .zshrc
or change HOME. Optional argument: directory in which to retain QA evidence.
"""
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile
import time

import pexpect

SOURCE = Path(__file__).resolve().parents[1] / "setup_tloggerV2.sh"
PROMPT = "__COLOUR_QA_READY__ "
SGR = re.compile(r"\x1b\[[0-9;]*m")
RESULTS = []


class Session:
    def __init__(self, root, name, pty_mode="n"):
        self.root = root / name
        self.root.mkdir()
        installer = self.root / "installer.sh"
        # Redirect the generated paths without changing the real HOME.
        installer.write_text(SOURCE.read_text().replace("$HOME", "$TLOGGER_QA_HOME"))
        (self.root / ".zshrc").write_text("alias ls='ls --color=auto'\n")
        env = dict(os.environ, TLOGGER_QA_HOME=str(self.root), TERM="xterm-256color",
                   SHELL="/usr/bin/zsh", LS_COLORS="di=01;34:ex=01;32")
        subprocess.run(["bash", str(installer), "install"],
                       input=f"1\n{pty_mode}\n", text=True, capture_output=True,
                       env=env, check=True)
        generated = (self.root / ".zshrc").read_text()
        # Validate the installed heredoc, since the installer expands it.
        relay = generated.split("<<'TLOGGER_PY'\n", 1)[1].split("\nTLOGGER_PY\n", 1)[0]
        compile(relay, str(self.root / ".zshrc") + ":relay", "exec")
        subprocess.run(["/usr/bin/zsh", "-n", str(self.root / ".zshrc")], check=True)
        runner = self.root / "runner"
        runner.mkdir()
        (runner / ".zshrc").write_text(
            f"source {shlex.quote(str(self.root / '.zshrc'))}\n"
            f"unsetopt zle promptsp\nPS1='{PROMPT}'\nPS2='__MORE__ '\nstty -echo\n")
        env["ZDOTDIR"] = str(runner)
        self.child = pexpect.spawn("/usr/bin/zsh", ["-di"], cwd=str(self.root),
                                   env=env, encoding="utf-8", timeout=12,
                                   dimensions=(30, 100))
        self.transcript = (self.root / "screen.txt").open("w")
        self.child.logfile_read = self.transcript
        self.child.expect_exact(PROMPT)
        self.cmd("stty -g > tty-before")

    def drain(self):
        # expect() consumes bytes already buffered after the prompt too.
        # read_nonblocking() alone would leave those for the next command.
        self.child.expect(pexpect.TIMEOUT, timeout=0.15)
        return self.child.before

    def cmd(self, command):
        self.child.sendline(command)
        self.child.expect_exact(PROMPT)
        return self.child.before + self.drain()

    def log(self):
        return "\n".join(p.read_text() for p in (self.root / "Desktop/logs").glob("*.log"))

    def close(self):
        try:
            self.cmd("stty -g > tty-after")
            check("terminal settings restored", (self.root / "tty-before").read_bytes()
                  == (self.root / "tty-after").read_bytes())
            self.cmd("tlogger_stop")
            self.child.sendline("exit")
            self.child.expect(pexpect.EOF)
        finally:
            self.child.close(force=True)
            self.transcript.close()


def check(name, passed):
    RESULTS.append({"name": name, "passed": bool(passed)})
    print(f"{'PASS' if passed else 'FAIL'} {name}", flush=True)


def exercise(root, pty_mode):
    session = Session(root, "pty-" + pty_mode, pty_mode)
    try:
        folder = session.root / "COLOURED_DIRECTORY"
        folder.mkdir()
        (session.root / "match.txt").write_text("MATCH_OUTPUT\n")
        (session.root / "before.txt").write_text("old line\n")
        (session.root / "after.txt").write_text("new line\n")
        (session.root / "probe.py").write_text(
            "import os, sys\n"
            "print('STDOUT_TTY=' + str(sys.stdout.isatty()))\n"
            "print('STDERR_TTY=' + str(sys.stderr.isatty()), file=sys.stderr)\n"
            "print('SIZE=' + str(os.get_terminal_size(1)) if sys.stdout.isatty() else 'PIPE')\n"
            "print('\\033[32mPYTHON_COLOUR\\033[0m' if sys.stdout.isatty() else 'NO_COLOUR')\n"
            "print('中文結果')\n")
        commands = {
            "ls automatic colour": "ls -d COLOURED_DIRECTORY",
            "grep automatic colour": "grep --color=auto MATCH match.txt",
            "git automatic colour": "git -c color.ui=auto --no-pager diff --no-index before.txt after.txt",
        }
        baseline = {name: session.cmd(command) for name, command in commands.items()}
        session.cmd("tlogger_start")
        for name, command in commands.items():
            output = session.cmd(command)
            check(f"pty={pty_mode}: {name}", bool(SGR.search(baseline[name]))
                  and bool(SGR.search(output)))

        output = session.cmd("python3 probe.py")
        check("stdout and stderr remain ttys", "STDOUT_TTY=True" in output
              and "STDERR_TTY=True" in output)
        check("original terminal dimensions", "columns=100, lines=30" in output)
        check("Python script colour", "\x1b[32mPYTHON_COLOUR\x1b[0m" in output)
        session.child.setwinsize(24, 80)
        output = session.cmd("python3 probe.py")
        check("resized terminal dimensions", "columns=80, lines=24" in output)

        session.cmd("ls -d COLOURED_DIRECTORY > redirected.txt")
        check("redirected file stays plain", (session.root / "redirected.txt").read_text()
              == "COLOURED_DIRECTORY\n")
        output = session.cmd("ls -d COLOURED_DIRECTORY | cat")
        check("upstream pipeline keeps native colour policy", not SGR.search(output)
              and "COLOURED_DIRECTORY" in output)
        output = session.cmd("env /bin/ls --color=auto -d COLOURED_DIRECTORY")
        check("env and absolute path retain colour", bool(SGR.search(output)))
        session.cmd("sh -c 'exit 42'")
        log = session.log()
        check("log has output rather than only command echoes",
              all(line in log.splitlines() for line in
                  ["PYTHON_COLOUR", "STDOUT_TTY=True", "STDERR_TTY=True", "中文結果", "[exit:42]"]))
        check("log contains no ANSI escapes", "\x1b" not in log)

        session.child.sendline("sleep 60")
        time.sleep(0.3)
        session.child.sendcontrol("z")
        session.child.expect_exact(PROMPT)
        session.drain()
        check("Ctrl-Z returns to original shell", "suspended" in session.cmd("jobs"))
        session.child.sendline("fg")
        time.sleep(0.3)
        session.child.sendcontrol("c")
        session.child.expect_exact(PROMPT)
        session.drain()
        check("fg and Ctrl-C preserve exit status", "[exit:130]" in session.log().splitlines())
        check("shell remains usable", "ALIVE" in session.cmd("printf 'ALIVE\\n'"))
        session.cmd("TLOGGER_COLOR=0")
        check("explicit legacy fallback", not SGR.search(session.cmd(commands["ls automatic colour"])))
        session.cmd("unset TLOGGER_COLOR")
        check("colour can be re-enabled", bool(SGR.search(session.cmd(commands["ls automatic colour"]))))
        # Exercise output lifetime, not just isatty(): a background writer
        # must not hold the next prompt hostage or lose its later bytes.
        started = time.monotonic()
        session.cmd("(sleep 1; printf 'BACKGROUND_%s\\n' FINISHED) &")
        check("background job does not block prompt", time.monotonic() - started < 0.9)
        session.cmd("sleep 1.2")
        check("late background output reaches log", "BACKGROUND_FINISHED" in session.log().splitlines())
        session.cmd("seq 1 5000")
        numbers = [int(line) for line in session.log().splitlines() if line.isdecimal()]
        check("large output is complete and ordered", numbers == list(range(1, 5001)))
        (session.root / "binary.py").write_text("import sys; sys.stdout.buffer.write(bytes(range(256)))\n")
        session.cmd("python3 binary.py > binary.out")
        check("binary file redirection is byte-exact", (session.root / "binary.out").read_bytes() == bytes(range(256)))
        session.cmd("print -l /proc/$$/fd/*(N) > fds-before")
        for _ in range(12):
            session.cmd(":")
        session.cmd("print -l /proc/$$/fd/*(N) > fds-after")
        check("relay descriptors are released", len((session.root / "fds-before").read_text().splitlines())
              == len((session.root / "fds-after").read_text().splitlines()))
        (session.root / "input.py").write_text(
            "import getpass\n"
            "answer = input('ENTER_NORMAL:')\n"
            "secret = getpass.getpass('ENTER_SECRET:')\n"
            "print('INPUT_OK' if answer == 'NORMAL_INPUT' and secret == 'QA_SECRET_NEVER_ECHO' else 'BAD_INPUT')\n")
        session.cmd("stty echo")
        session.child.sendline("python3 input.py")
        session.child.expect_exact("ENTER_NORMAL:")
        session.child.sendline("NORMAL_INPUT")
        session.child.expect_exact("ENTER_SECRET:")
        ordinary_input = session.child.before
        session.child.sendline("QA_SECRET_NEVER_ECHO")
        session.child.expect_exact(PROMPT)
        response = session.child.before + session.drain()
        session.cmd("stty -echo")
        check("ordinary stdin and hidden password input work", "NORMAL_INPUT" in ordinary_input and "INPUT_OK" in response)
        check("hidden input is absent from screen and log", "QA_SECRET_NEVER_ECHO" not in response
              and "QA_SECRET_NEVER_ECHO" not in session.log())
    finally:
        session.close()


def main():
    root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(tempfile.mkdtemp(prefix="tlogger-colour-"))
    root.mkdir(parents=True, exist_ok=True)
    for mode in ("n", "y"):
        exercise(root, mode)
    (root / "results.json").write_text(json.dumps(RESULTS, indent=2))
    print(f"{sum(r['passed'] for r in RESULTS)}/{len(RESULTS)} passed; evidence: {root}")
    return int(not all(r["passed"] for r in RESULTS))


if __name__ == "__main__":
    sys.exit(main())
