#!/usr/bin/env bash
# Regression tests for tlogger. Each case installs into a throwaway HOME and
# drives a real interactive zsh, so nothing here touches your own config.
#
#   ./tests/run_tests.sh
#
# Needs: zsh, python3, script(1), GNU sed. Run it on Linux - the target is
# Kali, and BSD sed does not understand the escapes the cleaner uses.
set -u

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
INSTALLER="$ROOT/setup_tloggerV2.sh"
DRIVER="$ROOT/tests/pty_driver.py"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0

pass() { printf '  ok    %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }

check() { # name, expected-substring, file
  if grep -qa -- "$2" "$3" 2>/dev/null; then pass "$1"; else fail "$1"; fi
}

check_absent() { # name, forbidden-substring, file
  # An empty or missing file would satisfy "not present" without proving
  # anything, so require real content before believing the absence.
  if [ ! -s "$3" ]; then
    fail "$1 (nothing was recorded at all)"
  elif grep -qa -- "$2" "$3" 2>/dev/null; then
    fail "$1"
  else
    pass "$1"
  fi
}

# install <home> <mode 1|2> <pty y|n>
install_into() {
  local home="$1" mode="$2" pty="$3"
  mkdir -p "$home"
  : > "$home/.zshrc"
  printf '%s\n%s\n' "$mode" "$pty" | HOME="$home" bash "$INSTALLER" install >/dev/null 2>&1
}

drive() { # home, transcript, commands...
  local home="$1" transcript="$2"
  shift 2
  python3 "$DRIVER" "$home" "$transcript" "$@" >/dev/null 2>&1
}

newest_log() { ls -t "$1"/Desktop/logs/*.log 2>/dev/null | head -1; }

echo "tlogger regression tests"
echo

echo "install shapes"
for shape in "n:without pty" "y:with pty"; do
  home="$WORK/shape_${shape%%:*}"
  install_into "$home" 2 "${shape%%:*}"
  if zsh -n "$home/.zshrc" 2>/dev/null; then
    pass "${shape##*:}: .zshrc parses"
  else
    fail "${shape##*:}: .zshrc parses"
  fi
done
check_absent "without pty: tlogger_pty is not defined" "tlogger_pty()" "$WORK/shape_n/.zshrc"
check "with pty: tlogger_pty is defined" "tlogger_pty()" "$WORK/shape_y/.zshrc"

echo
echo "core logging"
HOME_CORE="$WORK/core"
install_into "$HOME_CORE" 2 n
drive "$HOME_CORE" "$WORK/core.tty" \
  "echo HELLO_FROM_TEST" "false" "(exit 42)" "echo 中文測試" "tlogger_note MARKED"
LOG_CORE="$(newest_log "$HOME_CORE")"
check "command output is recorded"      "HELLO_FROM_TEST"  "$LOG_CORE"
check "a failing command records 1"     "[exit:1]"         "$LOG_CORE"
check "an explicit status is recorded"  "[exit:42]"        "$LOG_CORE"
check "utf-8 survives"                  "中文測試"          "$LOG_CORE"
check "notes are recorded"              "### NOTE"         "$LOG_CORE"
if [ "$(stat -c %a "$LOG_CORE" 2>/dev/null)" = 600 ]; then
  pass "log is created private"
else
  fail "log is created private"
fi

echo
echo "stop stays stopped"
HOME_STOP="$WORK/stop"
install_into "$HOME_STOP" 2 n
drive "$HOME_STOP" "$WORK/stop.tty" \
  "echo BEFORE_STOP" "tlogger_stop" "echo AFTER_STOP"
LOG_STOP="$(newest_log "$HOME_STOP")"
check        "output before stop is kept"  "BEFORE_STOP" "$LOG_STOP"
check_absent "nothing is kept after stop"  "AFTER_STOP"  "$LOG_STOP"

echo
echo "prompt plugins stay out of the log"
HOME_HOOK="$WORK/hook"
install_into "$HOME_HOOK" 2 n
# registered before tlogger's own hook, which is the case that used to leak
printf 'autoload -Uz add-zsh-hook\n_p() { print -r -- PLUGIN_NOISE; }\nadd-zsh-hook precmd _p\n%s' \
  "$(cat "$HOME_HOOK/.zshrc")" > "$HOME_HOOK/.zshrc.new"
mv "$HOME_HOOK/.zshrc.new" "$HOME_HOOK/.zshrc"
drive "$HOME_HOOK" "$WORK/hook.tty" "echo REAL_OUTPUT"
LOG_HOOK="$(newest_log "$HOME_HOOK")"
check        "the command's own output is kept" "REAL_OUTPUT"  "$LOG_HOOK"
check_absent "the plugin's output is not"       "PLUGIN_NOISE" "$LOG_HOOK"

echo
echo "interactive commands keep their terminal"
HOME_TTY="$WORK/tty"
install_into "$HOME_TTY" 2 n
PROBE="import sys; print('TTY' if sys.stdout.isatty() else 'PIPE')"
drive "$HOME_TTY" "$WORK/tty.tty" \
  "python3 -c \"$PROBE\"" "env -i PATH=/usr/bin:/bin python3 -c \"$PROBE\"" "/usr/bin/python3 -c \"$PROBE\""
if [ "$(tr -d '\r' < "$WORK/tty.tty" | grep -ac '^PIPE$')" = 0 ]; then
  pass "bare, env-wrapped and absolute paths all keep a tty"
else
  fail "bare, env-wrapped and absolute paths all keep a tty"
fi

echo
echo "job control is left alone"
HOME_JOB="$WORK/job"
install_into "$HOME_JOB" 2 n
drive "$HOME_JOB" "$WORK/job.tty" "sleep 60" "__CTRLZ__" "jobs" "kill %1"
check "a suspended job is still listed" "suspended" "$WORK/job.tty"

echo
echo "binary output does not corrupt the log"
HOME_BIN="$WORK/bin"
install_into "$HOME_BIN" 2 n
drive "$HOME_BIN" "$WORK/bin.tty" "head -c 300 /bin/true" "echo STILL_FINE"
LOG_BIN="$(newest_log "$HOME_BIN")"
check "logging continues afterwards" "STILL_FINE" "$LOG_BIN"
if file "$LOG_BIN" | grep -q text; then
  pass "the log is still text"
else
  fail "the log is still text"
fi

if [ -f "$WORK/shape_y/.zshrc" ]; then
  echo
  echo "pty capture"
  HOME_PTY="$WORK/pty"
  install_into "$HOME_PTY" 2 y
  drive "$HOME_PTY" "$WORK/pty.tty" \
    "ssh -o BatchMode=yes -o ConnectTimeout=1 -p 9999 127.0.0.1" \
    "env ssh -o BatchMode=yes -o ConnectTimeout=1 -p 9999 127.0.0.1" \
    "tlogger_pty add cd" "cd /tmp && pwd"
  LOG_PTY="$(newest_log "$HOME_PTY")"
  check "a captured session records its output"   "Connection refused" "$LOG_PTY"
  check "a wrapper-invoked one says why it did not" "bypasses the pty wrapper" "$LOG_PTY"
  check "builtins are refused"                    "is a shell builtin"  "$WORK/pty.tty"
  # the pwd output on its own line, not just any path that mentions /tmp
  if grep -qa '^/tmp$' "$LOG_PTY" 2>/dev/null; then
    pass "cd still works after that refusal"
  else
    fail "cd still works after that refusal"
  fi

  echo
  echo "interrupted captures are recovered"
  HOME_REC="$WORK/rec"
  install_into "$HOME_REC" 2 y
  printf 'EVIDENCE_FROM_A_DEAD_SHELL\n' > "${TMPDIR:-/tmp}/tlogger_pty.999999.TEST"
  drive "$HOME_REC" "$WORK/rec.tty" "echo started"
  LOG_REC="$(newest_log "$HOME_REC")"
  check "a dead shell's transcript is picked up" "EVIDENCE_FROM_A_DEAD_SHELL" "$LOG_REC"
  rm -f "${TMPDIR:-/tmp}"/tlogger_pty.999999.* 2>/dev/null
fi

echo
echo "uninstall"
HOME_UN="$WORK/uninstall"
install_into "$HOME_UN" 2 y
printf 'alias mine="echo keep me"\n' >> "$HOME_UN/.zshrc"
HOME="$HOME_UN" bash "$INSTALLER" uninstall >/dev/null 2>&1
check        "unrelated lines are kept" "keep me"        "$HOME_UN/.zshrc"
check_absent "the tlogger block is gone" "TLOGGER FINAL" "$HOME_UN/.zshrc"
check_absent "the pty block is gone"     "TLOGGER PTY"   "$HOME_UN/.zshrc"

echo
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
