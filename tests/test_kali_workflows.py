#!/usr/bin/env python3
"""Kali integration QA against disposable loopback services only.

Requires pexpect, nmap, ffuf, gobuster, feroxbuster, curl, nc, socat, vim, less.
No external targets, credentials, user configuration, or privileged services.
"""
import http.server
import json
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request

from test_colour import Session, PROMPT, RESULTS, check


class Handler(http.server.BaseHTTPRequestHandler):
    def handle(self):
        try:
            super().handle()
        except ConnectionResetError:
            pass  # Nmap's connect-only probe intentionally closes immediately.

    def do_GET(self):
        found = self.path in ("/", "/qa-found")
        body = b"DISPOSABLE_QA_HTTP_RESPONSE\n" if found else b"not found\n"
        self.send_response(200 if found else 404)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def tools_test(root):
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    port = server.server_address[1]
    url = f"http://127.0.0.1:{port}"
    session = Session(root, "tools")
    try:
        (session.root / "words.txt").write_text("qa-found\nmissing-qa\n")
        session.cmd("tlogger_start")
        output = session.cmd(f"nmap -sT -Pn -p {port} -oA scan 127.0.0.1")
        check("Nmap: loopback port and native XML saved", f"{port}/tcp open" in output
              and 'state="open"' in (session.root / "scan.xml").read_text())
        output = session.cmd(f"curl -fsS {url}/qa-found")
        check("curl: response visible and logged", "DISPOSABLE_QA_HTTP_RESPONSE" in output
              and "DISPOSABLE_QA_HTTP_RESPONSE" in session.log().splitlines())
        output = session.cmd(f"ffuf -u {url}/FUZZ -w words.txt -t 1 -rate 5 -mc 200 -c -of json -o ffuf.json")
        data = json.loads((session.root / "ffuf.json").read_text())
        check("ffuf: real result, colour and JSON artifact", "qa-found" in output
              and "\x1b[" in output and len(data["results"]) == 1)
        output = session.cmd(f"gobuster dir -u {url} -w words.txt -t 1 --no-progress -o gobuster.txt")
        check("Gobuster: result visible and saved", "qa-found" in output
              and "qa-found" in (session.root / "gobuster.txt").read_text())
        output = session.cmd(f"feroxbuster -u {url} -w words.txt -t 1 --rate-limit 5 --no-recursion --dont-extract-links --no-state -q -o ferox.txt")
        check("feroxbuster: result visible and saved", "qa-found" in output
              and "qa-found" in (session.root / "ferox.txt").read_text())
        check("enumeration results also reach log", session.log().count("qa-found") >= 4)
    finally:
        session.close()
        server.shutdown()
        server.server_close()


def http_test(root):
    session = Session(root, "python-http")
    port = free_port()
    try:
        (session.root / "transfer-fixture.txt").write_text("TRANSFER_QA_CONTENT")
        session.cmd("tlogger_start")
        session.child.sendline(f"python3 -m http.server {port} --bind 127.0.0.1")
        session.child.expect_exact("Serving HTTP")
        body = urllib.request.urlopen(f"http://127.0.0.1:{port}/transfer-fixture.txt", timeout=3).read()
        session.child.expect_exact('GET /transfer-fixture.txt HTTP/1.1')
        session.child.sendcontrol("c")
        session.child.expect_exact(PROMPT)
        session.drain()
        check("Python HTTP: transfer and request log survive Ctrl-C",
              body == b"TRANSFER_QA_CONTENT" and 'GET /transfer-fixture.txt HTTP/1.1' in session.log())
    finally:
        session.close()


def nc_test(root):
    session = Session(root, "nc-upgrade", "y")
    port = free_port()
    peer = None
    remote = None
    try:
        session.cmd("tlogger_start")
        session.child.sendline(f"nc -l -s 127.0.0.1 -p {port}")
        for _ in range(30):
            try:
                peer = socket.create_connection(("127.0.0.1", port), timeout=1)
                break
            except OSError:
                time.sleep(0.1)
        assert peer is not None, "local listener did not start"
        peer.settimeout(None)
        remote = subprocess.Popen(["/bin/bash", "--noprofile", "--norc"],
                                  stdin=peer, stdout=peer, stderr=peer, start_new_session=True)
        session.child.sendline("python3 -c 'import pty; pty.spawn([\"/bin/bash\", \"--noprofile\", \"--norc\"])'")
        time.sleep(0.3)
        session.child.sendcontrol("z")
        session.child.expect_exact(PROMPT)
        session.drain()
        check("nc: Ctrl-Z returns to local shell", "suspended" in session.cmd("jobs"))
        session.child.sendline("stty raw -echo; fg")
        time.sleep(0.3)
        # Construct the marker remotely: an echoed command cannot pass this.
        session.child.send("printf 'NC_%s\\n' UPGRADE_WORKED\r")
        session.child.expect_exact("NC_UPGRADE_WORKED")
        check("nc: raw/fg shell upgrade remains usable", True)
        session.child.send("exit\r")
        time.sleep(0.3)
        session.child.send("exit\n")
        remote.wait(timeout=5)
        peer.close()
        peer = None
        session.child.expect_exact(PROMPT)
        session.drain()
        session.cmd("stty $(cat tty-before)")
        check("nc: native session honestly remains unlogged", "NC_UPGRADE_WORKED" not in session.log())
    finally:
        if remote and remote.poll() is None:
            remote.terminate()
            remote.wait(timeout=3)
        if peer:
            peer.close()
        session.close()


def socat_test(root):
    session = Session(root, "socat-shell", "y")
    port = free_port()
    with (session.root / "server.txt").open("w") as output:
        server = subprocess.Popen(["socat", f"TCP-LISTEN:{port},bind=127.0.0.1,reuseaddr",
                                   "EXEC:/bin/bash --noprofile --norc,pty,stderr,setsid,sigint,sane"],
                                  stdout=output, stderr=output)
        try:
            time.sleep(0.2)
            session.cmd("tlogger_start")
            session.child.sendline(f"socat -,raw,echo=0 TCP:127.0.0.1:{port}")
            time.sleep(0.5)
            session.child.send("printf '\\033[32mSOCAT_%s\\033[0m\\n' CAPTURE_WORKED\r")
            session.child.expect_exact("\x1b[32mSOCAT_CAPTURE_WORKED\x1b[0m")
            session.child.send("exit\r")
            session.child.expect_exact(PROMPT)
            session.drain()
            check("socat: interactive shell colour and clean capture",
                  "SOCAT_CAPTURE_WORKED" in session.log().splitlines() and "\x1b" not in session.log())
        finally:
            if server.poll() is None:
                server.terminate()
            server.wait(timeout=3)
            session.close()


def tui_test(root):
    session = Session(root, "tui", "y")
    try:
        (session.root / "document.txt").write_text("".join(f"QA_LINE_{i:03d}\n" for i in range(100)))
        session.cmd("tlogger_start")
        session.child.sendline("vim -Nu NONE -n document.txt")
        session.child.expect_exact("QA_LINE_000")
        session.child.send("gg0iEDITED_\x1b")
        session.child.setwinsize(20, 70)
        session.child.send(":wq\r")
        session.child.expect_exact(PROMPT)
        session.drain()
        check("Vim: edit, resize and save", (session.root / "document.txt").read_text().startswith("EDITED_QA_LINE_000"))
        session.child.sendline("less document.txt")
        session.child.expect_exact("EDITED_QA_LINE_000")
        session.child.send("/QA_LINE_080\r")
        session.child.expect_exact("QA_LINE_080")
        session.child.send("q")
        session.child.expect_exact(PROMPT)
        session.drain()
        check("less: search and exit; native TUI is not recorded", "EDITED_QA_LINE_000" not in session.log())
        (session.root / "git-before").write_text("".join(f"GIT_OLD_{i:03d}\n" for i in range(100)))
        (session.root / "git-after").write_text("".join(f"GIT_NEW_{i:03d}\n" for i in range(100)))
        session.child.sendline("git -c core.pager='less -R' -c color.ui=auto diff --no-index git-before git-after")
        session.child.expect_exact("GIT_OLD_000")
        session.child.sendcontrol("z")
        session.child.expect_exact(PROMPT)
        session.drain()
        check("Git pager: Ctrl-Z returns to local shell", "suspended" in session.cmd("jobs"))
        session.child.sendline("fg")
        time.sleep(0.3)
        session.child.send("G")
        session.child.expect_exact("GIT_NEW_099")
        session.child.send("q")
        session.child.expect_exact(PROMPT)
        session.drain()
        check("Git: automatic pager scroll and exit", "GIT_NEW_099" in session.log())
    finally:
        session.close()


def main():
    root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(tempfile.mkdtemp(prefix="tlogger-workflows-"))
    root.mkdir(parents=True, exist_ok=True)
    for case in (tools_test, http_test, nc_test, socat_test, tui_test):
        try:
            case(root)
        except Exception as exc:
            check(case.__name__ + ": " + repr(exc), False)
    (root / "results.json").write_text(json.dumps(RESULTS, indent=2))
    print(f"{sum(r['passed'] for r in RESULTS)}/{len(RESULTS)} passed; evidence: {root}")
    return int(not all(r["passed"] for r in RESULTS))


if __name__ == "__main__":
    sys.exit(main())
