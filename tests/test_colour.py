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
        self.cmd("stty -g > tty-after")
        check("terminal settings restored", (self.root / "tty-before").read_bytes()
              == (self.root / "tty-after").read_bytes())
        self.cmd("tlogger_stop")
        self.child.sendline("exit")
        self.child.expect(pexpect.EOF)
        self.child.close()
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
