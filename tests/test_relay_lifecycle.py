#!/usr/bin/env python3
"""Fault, ordering, stop and recovery regressions in isolated Linux terminals."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

from test_colour import Session, PROMPT, RESULTS, check


def sink_failure(root):
    s = Session(root, 'sink-failure')
    try:
        (s.root / 'producer.py').write_text(
            "import os\nfrom pathlib import Path\n"
            "for i in range(100): os.write(1, (str(i)+':'+'x'*1024+'\\n').encode())\n"
            "Path('producer-result').write_text('complete')\n")
        # Leave room for zsh's relay heredoc temp file; fail the growing log.
        s.cmd('ulimit -f 64')
        s.cmd('tlogger_start')
        out = s.cmd('python3 producer.py')
        check('log size failure does not abort producer',
              (s.root / 'producer-result').read_text() == 'complete' and '99:' in out)
        check('log failure is reported once', out.count('log write failed') == 1)
        check('failed logging is paused', 'STOPPED' in s.cmd('tlogger_status'))
    finally:
        s.close()


def stop_background(root, colour):
    s = Session(root, 'stop-' + str(colour))
    try:
        s.cmd('TLOGGER_COLOR=' + str(colour))
        s.cmd('tlogger_start')
        s.cmd("(printf 'BEFORE_%s\\n' STOP; sleep 1.3; printf 'AFTER_%s\\n' STOP) &")
        check(f'colour={colour}: earlier background output saved', 'BEFORE_STOP' in s.log().splitlines())
        s.cmd('tlogger_stop')
        s.cmd('tlogger_start')
        s.child.expect_exact('AFTER_STOP', timeout=3)
        s.drain()
        check(f'colour={colour}: old relay shows output but never resumes logging', 'AFTER_STOP' not in s.log())
        s.cmd("printf 'NEW_%s\\n' SESSION")
        check(f'colour={colour}: new session records normally', 'NEW_SESSION' in s.log().splitlines())
    finally:
        s.close()


def ordering(root):
    s = Session(root, 'ordering')
    holder = None
    try:
        s.cmd('tlogger_start')
        s.cmd('print -rn -- $TLOGGER_STATE > state-path')
        state = (s.root / 'state-path').read_text()
        ready = s.root / 'locked'
        code = "import fcntl,sys,time;from pathlib import Path;f=open(sys.argv[1],'r+');fcntl.flock(f,fcntl.LOCK_EX);Path(sys.argv[2]).touch();time.sleep(.8)"
        holder = subprocess.Popen([sys.executable, '-c', code, state, str(ready)])
        for _ in range(100):
            if ready.exists(): break
            time.sleep(.01)
        s.cmd("printf 'FIRST_%s\\n' BODY")
        s.cmd("printf 'SECOND_%s\\n' BODY")
        lines = s.log().splitlines()
        check('foreground log write precedes next header despite delayed sink',
              lines.index('FIRST_BODY') < next(i for i, line in enumerate(lines) if line.startswith('└─$') and 'SECOND_' in line))
    finally:
        if holder:
            holder.wait(timeout=3)
        s.close()


def split_output(root):
    s = Session(root, 'split-output')
    try:
        payload = ('\x1b[38;2;10;20;30m中文結果\x1b[0m\r\n'
                   '\x1b]0;hidden title\x07VISIBLE_BEL\n'
                   '\x1b]8;;https://example.invalid\x1b\\LINK'
                   '\x1b]8;;\x1b\\\n'
                   'CTRL:\x00\x01\x08\x7fOK\tTAB\n'
                   'PROGRESS:1\rPROGRESS:2\n')
        (s.root / 'split.py').write_text(
            'import os,time\n'
            f'for value in {payload.encode()!r}:\n'
            ' os.write(1, bytes([value])); time.sleep(.003)\n')
        s.cmd('tlogger_start')
        screen = s.cmd('python3 split.py')
        log = s.log()
        check('split UTF-8 and colour survive on screen', '\x1b[38;2;10;20;30m中文結果\x1b[0m' in screen)
        check('split ANSI and UTF-8 produce complete plain log',
              '中文結果\nVISIBLE_BEL\nLINK\nCTRL:OK\tTAB\nPROGRESS:1\nPROGRESS:2\n' in log
              and '\x1b' not in log and 'hidden title' not in log
              and 'https://example.invalid' not in log)
    finally:
        s.close()


def background_pager(root):
    s = Session(root, 'background-pager')
    try:
        (s.root / 'document').write_text(''.join(f'PAGER_ROW_{i:03d}\n' for i in range(200)))
        s.cmd('tlogger_start')
        s.cmd('less document &')
        time.sleep(.3)
        check('background pager is stopped for tty input', 'suspended' in s.cmd('jobs'))
        s.child.sendline('fg')
        time.sleep(.3)
        s.child.send('G')
        s.child.expect_exact('PAGER_ROW_199')
        s.child.send('q')
        s.child.expect_exact(PROMPT)
        s.drain()
        check('background pager can be resumed and quit', True)
    finally:
        s.close()


def recovery(root):
    scratch = root / 'recovery-tmp'
    scratch.mkdir()
    previous = os.environ.get('TMPDIR')
    os.environ['TMPDIR'] = str(scratch)
    sessions = []
    try:
        sessions = [Session(root, f'recover-{i}', 'y') for i in range(3)]
        for s in sessions:
            s.cmd('_tlogger_clean_ansi() { sleep 0.6; cat; }')
            s.cmd('tlogger_start')
        orphan = scratch / 'tlogger_pty.99999999.TEST.claimed.99999998'
        orphan.write_text('RECOVER_ONCE\n' * 100)
        sessions[0].child.sendline('_tlogger_recover_orphans')
        for _ in range(100):
            if not orphan.exists(): break
            time.sleep(.01)
        for s in sessions[1:]:
            s.child.sendline('_tlogger_recover_orphans')
        for s in sessions:
            s.child.expect_exact(PROMPT)
            s.drain()
        counts = [s.log().splitlines().count('RECOVER_ONCE') for s in sessions]
        check('live re-claim excludes concurrent recoverers', sorted(counts) == [0, 0, 100])
        # Another interruption can leave a nested claim; it must be retried.
        (scratch / 'tlogger_pty.99999999.TEST.claimed.99999998.claimed.99999997').write_text('RECLAIM_AGAIN\n')
        sessions[0].cmd('_tlogger_recover_orphans')
        check('a second interrupted claim remains recoverable', 'RECLAIM_AGAIN' in sessions[0].log().splitlines())
    finally:
        for s in sessions:
            s.close()
        if previous is None:
            os.environ.pop('TMPDIR', None)
        else:
            os.environ['TMPDIR'] = previous


def main():
    root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(tempfile.mkdtemp(prefix='tlogger-lifecycle-'))
    root.mkdir(parents=True, exist_ok=True)
    for case in (sink_failure, lambda p: stop_background(p, 1), lambda p: stop_background(p, 0), ordering, split_output, background_pager, recovery):
        try:
            case(root)
        except Exception as exc:
            check(getattr(case, '__name__', 'case') + ': ' + repr(exc), False)
    (root / 'results.json').write_text(json.dumps(RESULTS, indent=2))
    print(f"{sum(r['passed'] for r in RESULTS)}/{len(RESULTS)} passed; evidence: {root}")
    return int(not all(r['passed'] for r in RESULTS))


if __name__ == '__main__':
    sys.exit(main())
