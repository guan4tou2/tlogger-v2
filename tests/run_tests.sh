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
echo "large output"
HOME_BIG="$WORK/big"
install_into "$HOME_BIG" 2 n
# seq, not a whitelisted command: something on TLOGGER_INTERACTIVE_CMDS is
# skipped by design, and testing with one measures nothing.
_old_settle="${TLOGGER_TEST_SETTLE:-2}"
export TLOGGER_TEST_SETTLE=4
drive "$HOME_BIG" "$WORK/big.tty" "seq 1 20000" "echo AFTER_BIG"
export TLOGGER_TEST_SETTLE="$_old_settle"
LOG_BIG="$(newest_log "$HOME_BIG")"
if [ "$(grep -acE '^[0-9]+$' "$LOG_BIG" 2>/dev/null)" = 20000 ]; then
  pass "20000 lines are all recorded"
else
  fail "20000 lines are all recorded ($(grep -acE '^[0-9]+$' "$LOG_BIG" 2>/dev/null) got through)"
fi
check "the next command is still recorded" "AFTER_BIG" "$LOG_BIG"

echo
echo "a log that cannot be written"
HOME_FULL="$WORK/full"
install_into "$HOME_FULL" 2 n
drive "$HOME_FULL" "$WORK/full.tty" \
  "TLOGGER_LOG=/dev/full" "echo ONE" "echo TWO" "echo THREE" "tlogger_status"
if [ "$(grep -ac 'logging stopped' "$WORK/full.tty")" = 1 ]; then
  pass "it gives up once instead of erroring on every prompt"
else
  fail "it gives up once instead of erroring on every prompt"
fi
check_absent "no internal errors reach the user" "tlogger_preexec:" "$WORK/full.tty"
if [ "$(tr -d '\r' < "$WORK/full.tty" | grep -acE '^(ONE|TWO|THREE)$')" = 3 ]; then
  pass "the commands themselves still run"
else
  fail "the commands themselves still run"
fi

echo
echo "hostile output"
HOME_W="$WORK/weird"
install_into "$HOME_W" 2 n
drive "$HOME_W" "$WORK/weird.tty" \
  "printf NO_TRAILING_NEWLINE" "echo AFTERWARDS" "exec 1>&-" "echo RECOVERED"
LOG_W="$(newest_log "$HOME_W")"
# the value must stay readable, not become NO_TRAILING_NEWLINE[exit:0]
if grep -qa '^NO_TRAILING_NEWLINE$' "$LOG_W" 2>/dev/null; then
  pass "output without a trailing newline is not glued to the marker"
else
  fail "output without a trailing newline is not glued to the marker"
fi
check_absent "closing stdout does not leak an internal error" "tlogger_capture_exit:" "$WORK/weird.tty"
check "logging recovers after stdout is closed" "RECOVERED" "$LOG_W"

HOME_SYM="$WORK/symlink"
install_into "$HOME_SYM" 1 n
mkdir -p "$HOME_SYM/Desktop/logs"
printf 'MUST_NOT_BE_TOUCHED\n' > "$WORK/bystander.txt"
# a symlink planted where the next log file will be created
ln -s "$WORK/bystander.txt" "$HOME_SYM/Desktop/logs/session_planted_UTC.log"
drive "$HOME_SYM" "$WORK/symlink.tty" \
  "TLOGGER_LOG=$HOME_SYM/Desktop/logs/session_planted_UTC.log tlogger_start"
if [ "$(cat "$WORK/bystander.txt")" = "MUST_NOT_BE_TOUCHED" ]; then
  pass "a symlinked log path is refused, not written through"
else
  fail "a symlinked log path is refused, not written through"
fi

echo
echo "manual mode"
HOME_MAN="$WORK/manual"
install_into "$HOME_MAN" 1 n
drive "$HOME_MAN" "$WORK/manual.tty" \
  "echo BEFORE_START" "tlogger_status" "tlogger_start" "echo WHILE_ON" \
  "tlogger_stop" "echo AFTER_OFF"
LOG_MAN="$(newest_log "$HOME_MAN")"
if [ -s "$LOG_MAN" ]; then pass "manual start creates a log"; else fail "manual start creates a log"; fi
check        "output while on is kept"        "WHILE_ON"      "$LOG_MAN"
check_absent "nothing from before the start"  "BEFORE_START"  "$LOG_MAN"
check_absent "nothing after the stop"         "AFTER_OFF"     "$LOG_MAN"
check        "status reports the mode"        "mode: manual"  "$WORK/manual.tty"

echo
echo "installer edge cases"
HOME_FRESH="$WORK/fresh"
mkdir -p "$HOME_FRESH"          # deliberately no .zshrc at all
printf '2\nn\n' | HOME="$HOME_FRESH" bash "$INSTALLER" install >/dev/null 2>&1
check "installs onto an account with no .zshrc" "TLOGGER FINAL" "$HOME_FRESH/.zshrc"
printf '2\nn\n' | HOME="$HOME_FRESH" bash "$INSTALLER" install > "$WORK/reinstall.out" 2>&1
if [ "$(grep -ac 'TLOGGER FINAL CLEAN START' "$HOME_FRESH/.zshrc")" = 1 ]; then
  pass "installing twice does not duplicate the block"
else
  fail "installing twice does not duplicate the block"
fi
check "installing twice says how to upgrade" "uninstall" "$WORK/reinstall.out"

echo
echo "logging that cannot start"
HOME_BAD="$WORK/cannot_start"
install_into "$HOME_BAD" 2 n
mkdir -p "$HOME_BAD/Desktop"
rm -rf "$HOME_BAD/Desktop/logs"
: > "$HOME_BAD/Desktop/logs"     # a file where the directory should be
drive "$HOME_BAD" "$WORK/bad.tty" "echo one" "echo two" "echo three"
if [ "$(grep -ac 'cannot create' "$WORK/bad.tty")" = 1 ]; then
  pass "the failure is reported once, not on every prompt"
else
  fail "the failure is reported once, not on every prompt"
fi
check "the shell stays usable" "three" "$WORK/bad.tty"

echo
echo "one log per terminal"
HOME_MULTI="$WORK/multi"
install_into "$HOME_MULTI" 2 n
drive "$HOME_MULTI" "$WORK/m1.tty" "echo TERMINAL_ONE" &
drive "$HOME_MULTI" "$WORK/m2.tty" "echo TERMINAL_TWO" &
wait
if [ "$(ls "$HOME_MULTI"/Desktop/logs/*.log 2>/dev/null | wc -l)" -ge 2 ]; then
  pass "two terminals get two files"
else
  fail "two terminals get two files"
fi
if [ "$(grep -la 'TERMINAL_ONE' "$HOME_MULTI"/Desktop/logs/*.log 2>/dev/null | wc -l)" = 1 ]; then
  pass "a command lands in exactly one of them"
else
  fail "a command lands in exactly one of them"
fi

if [ -f "$WORK/shape_y/.zshrc" ]; then
  echo
  echo "aliases and reloading"
  HOME_AL="$WORK/alias"
  install_into "$HOME_AL" 2 y
  printf "alias ls='echo REAL_LS_RAN'\n%s" "$(cat "$HOME_AL/.zshrc")" > "$HOME_AL/.zshrc.new"
  mv "$HOME_AL/.zshrc.new" "$HOME_AL/.zshrc"
  drive "$HOME_AL" "$WORK/alias.tty" \
    "tlogger_pty add ls" "ls" "tlogger_pty remove ls" "alias ls" \
    "source ~/.zshrc" "ssh -V"
  check "a captured command keeps the user's alias"  "REAL_LS_RAN"     "$WORK/alias.tty"
  check "removing it hands the alias back"           "echo REAL_LS_RAN" "$WORK/alias.tty"
  check "sourcing .zshrc again does not recurse"     "OpenSSH"          "$WORK/alias.tty"
  check_absent "no runaway recursion"                "FUNCNEST"         "$WORK/alias.tty"

  echo
  echo "quoting"
  HOME_Q="$WORK/quote"
  install_into "$HOME_Q" 2 y
  drive "$HOME_Q" "$WORK/quote.tty" \
    "ssh -o BatchMode=yes -o ConnectTimeout=1 -p 9999 127.0.0.1 'echo a; echo b'"
  LOG_Q="$(newest_log "$HOME_Q")"
  check "an operator inside quotes is not a pipeline" "Connection refused" "$LOG_Q"
fi

echo
echo "convenience commands refuse politely"
HOME_C="$WORK/conv"
install_into "$HOME_C" 1 n
drive "$HOME_C" "$WORK/conv.tty" \
  "tlogger_note nothing is running" "tlogger_grep anything" "tlogger_mode auto" "tlogger_mode"
check "a note without logging says so"  "not active"      "$WORK/conv.tty"
check "grep with no logs says so"       "no session logs" "$WORK/conv.tty"
check "the mode can be switched"        "mode: automatic" "$WORK/conv.tty"

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
