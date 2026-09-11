#!/usr/bin/env bash
set -e

ACTION="$1"
ZSHRC="$HOME/.zshrc"
BACKUP="$HOME/.zshrc_tlogger_backup"
LOGDIR="$HOME/Desktop/logs"

RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
MAGENTA="\033[1;35m"
CYAN="\033[1;36m"
WHITE="\033[1;37m"
RESET="\033[0m"

phoenix_banner='
--------------------------------------------------------
--------------------------------------------------------
------------------##----------------##------------------
---------------###+-------------------###---------------
-------------##-#----------------------#+##-------------
-------------#-#------------------------#-##------------
----------#-+#-#------------------------##-#-#----------
---------##--#-#-------------------------#-#-##---------
--------####-#-#-------------------------#-#-#+#--------
--------#+-#-#-#------------------------######+#--------
--------#-#-##-##-----------------------#--#####--------
--------#######-#-----------------------######+#--------
-------#-#######------------------------#-###+#-+-------
-------##-##+#-#-------------------------#####-##-------
-------#-##-#+-#-#-----------------------#-##-###-------
-------###-#####-##-----------##------#-#########-------
--------#-#######-##------#####-----##+-##-###+#--------
---------##-######-###---#####+---####-#-####+#---------
-----------+###-+##-###----#-##--###-##--####-----------
-----------###---#+-####--###+#-##-####+--+###----------
------------###--#-##-###-#-#-#-#--####---+#------------
--------------####-##-#######-##-#-##-####--------------
----------------###---##++-####-##+--###----------------
-------------------##---##-##-##---##-------------------
-------------------------####-#-------------------------
------------------------##-#####------------------------
------------------------######-##-----------------------
-----------------------######-###-----------------------
----------------------############----------------------
------------------------#####+##-+----------------------
-----------------------######-#+#-----------------------
-----------------------#-####-#-#-----------------------
------------------------##-##-###-----------------------
-------------------------#-##-##------------------------
----------------------------#-#-------------------------
----------------------------#---------------------------
----------------------------#---------------------------
--------------------------------------------------------
--------------------------------------------------------
'

flash_banner() {
  clear 2>/dev/null || true
  echo -e "${MAGENTA}${phoenix_banner}${RESET}"
  echo
  echo -e "${YELLOW}This script was originally called tlogger${RESET}"
  echo -e "${CYAN}Credits and initial creation to my brother-in-arms in April 2022:${RESET} ${GREEN}Salar${RESET}"
  echo -e "${BLUE}Enhanced and extended in Dec 2025 by:${RESET} ${RED}Ph03n1x${RESET}"
  echo -e "${WHITE}For the Hacktrack Session Report Writing for Penetration Testers – Offensive Security${RESET}"
  echo
  echo -e "${RED}♥ ${MAGENTA}From Ph03n1x & Salar with <3 ${RESET}"
}

ask_mode() {
  echo
  echo -e "${CYAN}Select logging mode:${RESET}"
  echo -e "${GREEN}  1) Manual${RESET}   → tlogger_start / tlogger_stop"
  echo -e "${YELLOW}  2) Automatic${RESET} → starts on every new terminal"
  echo
  read -rp "Choice [1/2]: " MODE
  case "$MODE" in
    1) AUTOSTART=0 ;;
    2) AUTOSTART=1 ;;
    *) echo "Invalid choice"; exit 1 ;;
  esac
}

ask_pty() {
  echo
  echo -e "${CYAN}Also capture interactive sessions through a pty?${RESET}"
  echo -e "${GREEN}  y) Yes${RESET}  ssh sessions recorded in full, adds tlogger_pty"
  echo -e "${YELLOW}  n) No ${RESET}  command output only, ~190 fewer lines in .zshrc"
  echo
  read -rp "Choice [y/N]: " WANT_PTY
  case "$WANT_PTY" in
    y|Y|yes|YES) WANT_PTY=1 ;;
    *) WANT_PTY=0 ;;
  esac
}

print_usage() {
cat <<'USAGE'

TLOGGER – Terminal Session Logger

Install:
  ./setup_tloggerV2.sh install

Uninstall:
  ./setup_tloggerV2.sh uninstall

Manual mode:
  tlogger_start
  tlogger_stop

Automatic mode:
  Logging starts automatically in every new terminal

While logging:
  tlogger_status              is it running, where, how big
  tlogger_note "found creds"  drop a marker into the log
  tlogger_grep <pattern>      search every session log
  tlogger_mode auto|manual    switch mode without reinstalling

Logs:
  ~/Desktop/logs/session_<UTC_TIMESTAMP>_<PID>_UTC.log
  One file per terminal; each entry ends with its exit code.

USAGE
  # Only listed when it exists - a minimal install has no such command.
  if [ "${WANT_PTY:-0}" -eq 1 ]; then
cat <<'PTYUSAGE'
Pty capture:
  tlogger_pty list            show which commands are captured
  tlogger_pty add <cmd>       capture one through a pty (this shell only)

PTYUSAGE
  fi
}

print_reload_hint() {
  echo -e "${YELLOW}[!] This shell was started before the install, so the tlogger${RESET}"
  echo -e "${YELLOW}    commands are not defined in it yet. Start a new terminal, or:${RESET}"
  echo -e "${GREEN}      exec zsh${RESET}"
  echo
}

write_pty_block() {
  cat >> "$ZSHRC" <<EOF

### TLOGGER PTY CAPTURE ###

# Captured through a real pty via script(1): the session renders normally
# on screen AND the full transcript goes into the log.
# Add any interactive command you want recorded, e.g. (ssh msfconsole mysql)
TLOGGER_PTY_CMDS=(ssh socat pwncat-cs)

# Taking over a command name would silently drop an alias the user already
# had - Kali ships "ls --color=auto" - so remember it and keep using it.
typeset -gA TLOGGER_PTY_ORIG

_tlogger_pty_alias() {
  local _c="\$1"
  local _existing="\${aliases[\$_c]:-}"
  # Sourcing .zshrc again would otherwise store our own wrapper as the
  # "original" and the command would call itself until FUNCNEST is hit.
  if [[ "\$_existing" == "_tlogger_pty_run "* ]]; then
    :
  elif [[ -n "\$_existing" ]]; then
    # Take the current definition every time, so editing the alias and
    # sourcing again is picked up instead of keeping the stale one.
    TLOGGER_PTY_ORIG[\$_c]="\$_existing"
  fi
  alias "\$_c"="_tlogger_pty_run \$_c"
}

# On a reload, hand back any command that has since been taken off the list.
_tlogger_pty_sync() {
  local _c
  for _c in "\${(@k)TLOGGER_PTY_ORIG}"; do
    (( \${TLOGGER_PTY_CMDS[(I)\$_c]} )) && continue
    [[ "\${aliases[\$_c]:-}" == "_tlogger_pty_run "* ]] && alias "\$_c"="\${TLOGGER_PTY_ORIG[\$_c]}"
    unset "TLOGGER_PTY_ORIG[\$_c]"
  done
  for _c in "\${(@k)aliases}"; do
    [[ "\${aliases[\$_c]}" == "_tlogger_pty_run "* ]] || continue
    (( \${TLOGGER_PTY_CMDS[(I)\$_c]} )) && continue
    unalias "\$_c" 2>/dev/null
  done
}

_tlogger_pty_run() {
  setopt local_options no_err_exit unset
  local _tlogger_cmd="\$1"
  shift
  local _tlogger_real="\${TLOGGER_PTY_ORIG[\$_tlogger_cmd]:-command \$_tlogger_cmd}"
  # An alias body is shell text, so it has to be re-parsed rather than split
  # into words: quoting, and expansions such as \$PWD that are meant to run
  # at call time, only survive evaluation.
  if [[ -z "\$TLOGGER_ACTIVE" ]] || [[ ! -t 0 ]] || [[ ! -t 1 ]] \
     || ! command -v script >/dev/null 2>&1; then
    eval "\$_tlogger_real \\"\\\$@\\""
    return \$?
  fi
  local _tlogger_tmp
  # The pid is in the name so an interrupted capture can be identified and
  # recovered later; see _tlogger_recover_orphans.
  _tlogger_tmp="\$(mktemp -t tlogger_pty.\$\$.XXXXXX)" || {
    eval "\$_tlogger_real \\"\\\$@\\""
    return \$?
  }
  # -f flushes after every write: without it the transcript can still be
  # sitting in a buffer when the terminal is killed, leaving nothing to
  # recover even though the screen showed the output.
  script -qef -c "\$_tlogger_real \${(j: :)\${(qq)@}}" "\$_tlogger_tmp"
  local _tlogger_rc=\$?
  if [[ ! -s "\$_tlogger_tmp" ]]; then
    rm -f "\$_tlogger_tmp"
  elif _tlogger_clean_ansi < "\$_tlogger_tmp" >> "\$TLOGGER_LOG" 2>/dev/null; then
    rm -f "\$_tlogger_tmp"
  else
    # The merge failed (a full disk): keep the transcript, it is the only
    # copy. This shell's next tlogger_start, or another shell's once this one
    # exits, recovers it. Deleting it here is the data loss we are avoiding.
    echo "[tlogger] could not save the captured session to the log; kept at \$_tlogger_tmp" >&2
  fi
  return \$_tlogger_rc
}

for _tlogger_pc in \$TLOGGER_PTY_CMDS; do
  _tlogger_pty_alias "\$_tlogger_pc"
done
unset _tlogger_pc
_tlogger_pty_sync

# A pty capture is only merged into the log once the command finishes, so a
# terminal killed mid-command leaves its transcript stranded in the temp
# file. Pick up anything left behind by a shell that is no longer running.
_tlogger_recover_orphans() {
  setopt local_options null_glob unset
  local _f _pid _claim _claimpid
  for _f in "\${TMPDIR:-/tmp}"/tlogger_pty.*(.N); do
    if [[ "\$_f" == *.claimed.* ]]; then
      # A claim left behind by a recoverer that died before merging. If its
      # claimer is still alive, leave it be; otherwise re-process it, or its
      # contents would be skipped forever.
      _claimpid="\${_f##*.claimed.}"
      [[ "\$_claimpid" == <-> ]] && kill -0 "\$_claimpid" 2>/dev/null && continue
      _pid="\${\${_f:t}#tlogger_pty.}"
      _pid="\${_pid%%.*}"
      # Re-claim atomically, exactly like a fresh file: two terminals racing on
      # the same dead claim must not both import it (that doubled the lines).
      # Whoever wins the rename owns it; the loser's mv fails and it moves on.
      _claim="\${_f}.claimed.\$\$"
      mv -- "\$_f" "\$_claim" 2>/dev/null || continue
    else
      _pid="\${\${_f:t}#tlogger_pty.}"
      _pid="\${_pid%%.*}"
      [[ "\$_pid" == <-> ]] || continue
      kill -0 "\$_pid" 2>/dev/null && continue

      # Claim by rename: whoever wins the rename owns the file, so two
      # terminals starting at once cannot both import the same transcript.
      _claim="\${_f}.claimed.\$\$"
      mv -- "\$_f" "\$_claim" 2>/dev/null || continue
    fi

    if [[ -s "\$_claim" ]]; then
      # Only drop the source once it is safely in the log: on a full disk
      # this is the sole copy of that session.
      if printf "\\n### RECOVERED from an interrupted capture (pid %s) ###\\n" "\$_pid" \
           >> "\$TLOGGER_LOG" 2>/dev/null \
         && _tlogger_clean_ansi < "\$_claim" >> "\$TLOGGER_LOG" 2>/dev/null; then
        rm -f -- "\$_claim"
      else
        echo "[tlogger] could not write recovered transcript; kept at \$_claim" >&2
        mv -- "\$_claim" "\$_f" 2>/dev/null
        return 1
      fi
    else
      rm -f -- "\$_claim"
    fi
  done
  return 0
}

tlogger_pty() {
  setopt local_options no_err_exit unset
  local _c _tlogger_changed=0
  case "\$1" in
    add)
      shift
      [[ \$# -eq 0 ]] && { echo "usage: tlogger_pty add <cmd>..."; return 1; }
      for _c in "\$@"; do
        # The name becomes an alias, so keep it to something that can
        # actually be one.
        # Strip every allowed character; anything left over is not a name we
        # can safely write into .zshrc. Avoids depending on extended_glob.
        if [[ -z "\$_c" || -n "\${_c//[A-Za-z0-9_.+-]/}" ]]; then
          echo "[tlogger] \$_c is not a plain command name — not added"
          continue
        fi
        if (( \${TLOGGER_PTY_CMDS[(I)\$_c]} )); then
          echo "[tlogger] \$_c is already captured"
          continue
        fi
        # A builtin has to run in this shell; routing it through a pty would
        # execute it in a child, where cd or export changes nothing here.
        if (( \${+builtins[\$_c]} )) || (( \${reswords[(I)\$_c]} )); then
          echo "[tlogger] \$_c is a shell builtin and must run in this shell — not added"
          continue
        fi
        # A function lives in this shell only; "command" inside the wrapper
        # would look for an external program of that name and find nothing.
        if (( \${+functions[\$_c]} )); then
          echo "[tlogger] \$_c is a shell function and cannot be run through a pty — not added"
          continue
        fi
        if ! command -v "\$_c" >/dev/null 2>&1 && [[ -z "\${aliases[\$_c]}" ]]; then
          echo "[tlogger] warning: \$_c was not found in PATH — adding anyway"
        fi
        TLOGGER_PTY_CMDS+=("\$_c")
        _tlogger_changed=1
        _tlogger_pty_alias "\$_c"
        echo "[tlogger] \$_c is now captured through a pty"
        # script(1) owns the pty, so Ctrl-Z stops inside it instead of
        # handing the shell back. It matters most for a caught shell, where
        # Ctrl-Z then "stty raw -echo; fg" is the usual upgrade.
        echo "           note: Ctrl-Z will not suspend \$_c while it is captured"
      done
      (( _tlogger_changed )) && cat <<'TLHINT'
[tlogger] this shell only. To keep it, edit the TLOGGER_PTY_CMDS line in
          ~/.zshrc - tlogger does not rewrite your config while running.
TLHINT
      ;;
    remove|rm)
      shift
      [[ \$# -eq 0 ]] && { echo "usage: tlogger_pty remove <cmd>..."; return 1; }
      for _c in "\$@"; do
        if (( ! \${TLOGGER_PTY_CMDS[(I)\$_c]} )); then
          echo "[tlogger] \$_c is not in the list"
          continue
        fi
        TLOGGER_PTY_CMDS=("\${(@)TLOGGER_PTY_CMDS:#\$_c}")
        _tlogger_changed=1
        if [[ -n "\${TLOGGER_PTY_ORIG[\$_c]:-}" ]]; then
          alias "\$_c"="\${TLOGGER_PTY_ORIG[\$_c]}"
          unset "TLOGGER_PTY_ORIG[\$_c]"
        else
          unalias "\$_c" 2>/dev/null
        fi
        echo "[tlogger] \$_c is no longer captured"
      done
      (( _tlogger_changed )) && cat <<'TLHINT'
[tlogger] this shell only. To keep it, edit the TLOGGER_PTY_CMDS line in
          ~/.zshrc - tlogger does not rewrite your config while running.
TLHINT
      ;;
    ''|list)
      echo "[tlogger] captured through a pty: \$TLOGGER_PTY_CMDS"
      echo "          add more with: tlogger_pty add <cmd>..."
      ;;
    *)
      echo "usage: tlogger_pty [list|add <cmd>...|remove <cmd>...]"
      return 1
      ;;
  esac
}

### TLOGGER PTY CAPTURE END ###
EOF
}

install() {
  if ! command -v zsh >/dev/null 2>&1; then
    echo -e "${RED}[!] zsh was not found on this system.${RESET}"
    echo -e "    TLOGGER is built on zsh's precmd/preexec hooks and cannot run"
    echo -e "    under bash or sh. Install zsh first: sudo apt install zsh"
    exit 1
  fi

  flash_banner
  ask_mode
  ask_pty

  case "$SHELL" in
    *zsh) ;;
    *)
      echo
      echo -e "${YELLOW}[i] Your login shell is $SHELL, not zsh.${RESET}"
      echo -e "    TLOGGER only records inside zsh sessions. Switch with:"
      echo -e "${GREEN}      chsh -s \$(command -v zsh)${RESET}"
      ;;
  esac

  mkdir -p "$LOGDIR"

  # A fresh account may not have one yet; without this the backup below
  # fails and set -e aborts the install.
  [ -f "$ZSHRC" ] || touch "$ZSHRC"

  if [ ! -f "$BACKUP" ]; then
    cp "$ZSHRC" "$BACKUP"
  fi

  if grep -q "### TLOGGER FINAL CLEAN START ###" "$ZSHRC"; then
    echo -e "${YELLOW}[i] TLOGGER is already installed in ${ZSHRC}.${RESET}"
    echo -e "    Re-running install does not update the block or change the mode."
    echo -e "    To upgrade or switch mode, remove it first:"
    echo -e "${GREEN}      $0 uninstall && $0 install${RESET}"
    echo
    print_usage
    exit 0
  fi

  # Check before appending: the block's own comments mention these names.
  THEME_DETECTED=0
  if grep -qE 'powerlevel10k|powerlevel9k|starship|spaceship|oh-my-zsh|ZSH_THEME' "$ZSHRC" 2>/dev/null; then
    THEME_DETECTED=1
  fi

  cat >> "$ZSHRC" <<EOF

### TLOGGER FINAL CLEAN START ###

export DISABLE_AUTO_TITLE=true
export TLOGGER_AUTOSTART=$AUTOSTART

tun0_ip() {
  ip -4 addr show tun0 2>/dev/null | awk '/inet /{print \$2}' | cut -d/ -f1
}

# The prompt is deliberately left alone. Prompt frameworks such as
# powerlevel10k re-render asynchronously and will fight any takeover; the
# per-command log header already records user, host, cwd, UTC time and the
# tun0 address, so nothing is lost by staying out of the way.

tlogger_capture_exit() {
  TLOGGER_LAST_EXIT=\$?
  setopt local_options no_err_exit unset
  # Everything a command produced must be closed out, and stdout handed
  # back, before any other precmd hook runs - otherwise a prompt plugin
  # that prints gets recorded as if the command had produced it.
  if [[ -n "\${TLOGGER_LAST_LOGGED:-}" && -n "\${TLOGGER_LOG:-}" ]]; then
    if [[ -n "\${TLOGGER_LAST_PIPED:-}" ]]; then
      # Leading newline: output that ended without one would otherwise have
      # the marker stuck to it, turning "hash" into "hash[exit:0]".
      printf "\\n[exit:%d]\\n" "\$TLOGGER_LAST_EXIT" 2>/dev/null
    else
      printf "\\n[exit:%d]\\n" "\$TLOGGER_LAST_EXIT" >> "\$TLOGGER_LOG" 2>/dev/null
    fi
    unset TLOGGER_LAST_LOGGED TLOGGER_LAST_PIPED
  fi
  [[ -n "\${TLOGGER_OUTPUT_TOKEN:-}" ]] \
    && printf '\\033]tlogger-finish;%s\\007' "\$TLOGGER_OUTPUT_TOKEN" 2>/dev/null
  [[ -n "\${TLOGGER_ACTIVE:-}" || -n "\${TLOGGER_OUTPUT_FD:-}" ]] && exec >/dev/tty 2>&1
  _tlogger_finish_output
  return 0
}

_tlogger_clean_ansi() {
  # "|" as the delimiter so the 0x20-0x2F intermediate range can contain "/"
  # without an escape - inside a bracket expression a backslash is literal,
  # and "[ -\/]" silently becomes the range 0x20-0x5C, which swallows text.
  LC_ALL=C sed -r \
    -e 's|\\x1B\\][^\\a]*\\a||g' \
    -e 's|\\x1B\\][^\\x1B]*\\x1B\\\\||g' \
    -e 's|\\x1B\\[[0-9;:<=>?]*[ -/]*[@-~]||g' \
    -e 's|\\x1B[=>McD78EHZ]||g' \
    -e 's|\\r\$||' \
    -e '/^Script (started|done) on .*\\[.*\\]\$/d' \
    | tr -d '\\000-\\010\\013\\014\\016-\\037\\177' \
    | iconv -c -f UTF-8 -t UTF-8
}

# One locked state file is shared by this session's output relays. Stopping
# recording revokes log writes; it never closes a running tool's terminal.
_tlogger_disable_state() {
  setopt local_options no_err_exit unset
  local _state="\${TLOGGER_STATE:-}" _lock
  [[ -f "\$_state" ]] || return 0
  zmodload zsh/system || return 1
  zsystem flock -f _lock "\$_state" || return 1
  print -rn -- 0 >| "\$_state"
  rm -f -- "\$_state"
  zsystem flock -u "\$_lock"
}

_tlogger_exit_state() {
  (( ZSH_SUBSHELL == 0 )) && [[ "\${TLOGGER_STATE_OWNER:-}" == "\$\$" ]] && _tlogger_disable_state
  return 0
}

_tlogger_finish_output() {
  setopt local_options no_err_exit unset
  if [[ -n "\${TLOGGER_OUTPUT_FD:-}" ]]; then
    local _done
    # The private boundary follows foreground output in the same byte stream.
    # Its acknowledgement follows the actual log write, not a cleaner pipe.
    if ! IFS= read -r -t 5 -u "\$TLOGGER_OUTPUT_FD" _done; then
      echo '[tlogger] output completion was not confirmed; logging paused.' >&2
      unset TLOGGER_ACTIVE
      export TLOGGER_PAUSED=1
      _tlogger_disable_state
    elif [[ "\$_done" == failed ]]; then
      unset TLOGGER_ACTIVE
      export TLOGGER_PAUSED=1
      _tlogger_disable_state
    fi
    exec {TLOGGER_OUTPUT_FD}<&-
    unset TLOGGER_OUTPUT_FD TLOGGER_OUTPUT_TOKEN
  fi
  return 0
}

_tlogger_output_pty() {
  command python3 - "\$TLOGGER_LOG" "\$TLOGGER_STATE" "\${TLOGGER_COLOR:-1}" <<'TLOGGER_PY'
import codecs
import errno
import fcntl
import os
from pathlib import Path
import pty
import secrets
import select
import signal
import sys
import termios

for sig in (signal.SIGINT, signal.SIGQUIT, signal.SIGTSTP,
            signal.SIGTTOU, signal.SIGTTIN, signal.SIGXFSZ):
    signal.signal(sig, signal.SIG_IGN)
log_path, state_path, colour = sys.argv[1:]
use_tty = colour != '0'
master, slave = pty.openpty() if use_tty else os.pipe()
slave_name = os.ttyname(slave) if use_tty else f'/proc/{os.getpid()}/fd/{slave}'
terminal = os.open('/dev/tty', os.O_RDWR | os.O_NOCTTY)
original_attrs = termios.tcgetattr(terminal)
shell_group = os.tcgetpgrp(terminal)
session_id = os.getsid(0)
if use_tty:
    attrs = original_attrs[:]
    attrs[1] &= ~termios.OPOST
    termios.tcsetattr(slave, termios.TCSANOW, attrs)
    last_attrs = termios.tcgetattr(slave)
mirrored_input = False
input_group = None
stopped_group = None
size = None
state_fd = log_fd = None
failed = False
finished = False
token = secrets.token_hex(16)
boundary = ('\x1b]tlogger-finish;' + token + '\x07').encode()
pending = b''

def write_all(fd, data):
    while data:
        data = data[os.write(fd, data):]

class Cleaner:
    # Incremental UTF-8/ANSI parsing keeps split multibyte characters and
    # escape sequences correct without a subprocess or delayed pipe buffer.
    def __init__(self):
        self.decoder = codecs.getincrementaldecoder('utf-8')('ignore')
        self.mode = 'text'
        self.cr = False

    def feed(self, data, final=False):
        out = []
        for char in self.decoder.decode(data, final):
            if self.mode == 'esc':
                if char == '[':
                    self.mode = 'csi'
                    continue
                if char == ']':
                    self.mode = 'osc'
                    continue
                self.mode = 'text'
                if char in '=>McD78EHZ':
                    continue
            elif self.mode == 'csi':
                if '@' <= char <= '~':
                    self.mode = 'text'
                continue
            elif self.mode == 'osc':
                if char == '\x07':
                    self.mode = 'text'
                elif char == '\x1b':
                    self.mode = 'osc-esc'
                continue
            elif self.mode == 'osc-esc':
                self.mode = 'text' if char == chr(92) else 'osc'
                continue
            if char == '\x1b':
                self.mode = 'esc'
                continue
            if ord(char) < 32 and char not in '\t\n\r' or char == '\x7f':
                continue
            if self.cr and char != '\n':
                out.append('\r')
            self.cr = char == '\r'
            if not self.cr:
                out.append(char)
        return ''.join(out).encode('utf-8')

cleaner = Cleaner()

def log_bytes(data):
    global failed, state_fd, log_fd
    if failed:
        return
    try:
        if state_fd is None:
            state_fd = os.open(state_path, os.O_RDWR)
        fcntl.flock(state_fd, fcntl.LOCK_EX)
        try:
            if os.pread(state_fd, 1, 0) != b'1':
                return
            if log_fd is None:
                log_fd = os.open(log_path, os.O_WRONLY | os.O_APPEND)
            write_all(log_fd, data)
        finally:
            fcntl.flock(state_fd, fcntl.LOCK_UN)
    except FileNotFoundError:
        # A stopped session unlinks its state after marking it inactive.
        if os.path.exists(state_path):
            failed = True
    except OSError:
        failed = True
    if failed:
        if state_fd is not None:
            try:
                fcntl.flock(state_fd, fcntl.LOCK_EX)
                os.pwrite(state_fd, b'0', 0)
            except OSError:
                pass
            finally:
                fcntl.flock(state_fd, fcntl.LOCK_UN)
        write_all(terminal, b'\n[tlogger] log write failed; screen output continues.\n')

def emit(data):
    if data:
        log_bytes(cleaner.feed(data))
        write_all(terminal, data)

def acknowledge():
    global finished
    if not finished:
        try:
            write_all(1, b'failed\n' if failed else b'done\n')
        except OSError:
            pass
        finished = True

def consume(data):
    global pending
    pending += data
    index = pending.find(boundary)
    if index >= 0:
        emit(pending[:index])
        acknowledge()
        pending = pending[index + len(boundary):]
    # Retain only a possible partial private boundary, never whole lines.
    keep = min(len(pending), len(boundary) - 1)
    while keep and not boundary.startswith(pending[-keep:]):
        keep -= 1
    if keep:
        emit(pending[:-keep])
        pending = pending[-keep:]
    else:
        emit(pending)
        pending = b''

def resize():
    global size
    current = fcntl.ioctl(terminal, termios.TIOCGWINSZ, b'\0' * 8)
    if use_tty and current != size:
        fcntl.ioctl(master, termios.TIOCSWINSZ, current)
        size = current

def reader_group():
    # A raw-mode change alone does not identify its owner. less opens the
    # slave for reading; locate that actual reader in this terminal session.
    # stdout-only writers and the shell are deliberately excluded.
    for proc in Path('/proc').glob('[0-9]*'):
        try:
            fields = (proc / 'stat').read_text().rsplit(')', 1)[1].split()
            group, sid = int(fields[2]), int(fields[3])
            if sid != session_id or group == shell_group or int(proc.name) == os.getpid():
                continue
            for fd in (proc / 'fd').iterdir():
                if os.readlink(fd) != slave_name:
                    continue
                info = (proc / 'fdinfo' / fd.name).read_text().splitlines()
                flags = int(next(x.split()[1] for x in info if x.startswith('flags:')), 8)
                if flags & os.O_ACCMODE != os.O_WRONLY:
                    return group
        except (OSError, ValueError, StopIteration):
            continue
    return None

def sync_input():
    global last_attrs, mirrored_input, input_group, stopped_group
    if not use_tty:
        return False
    current = termios.tcgetattr(master)
    foreground = os.tcgetpgrp(terminal)
    if current != last_attrs:
        if not current[3] & termios.ICANON:
            if input_group is None:
                input_group = reader_group()
            if input_group is None:
                return False
            if foreground != input_group:
                if stopped_group != input_group:
                    os.killpg(input_group, signal.SIGTTIN)
                    stopped_group = input_group
                return False
            os.setpgid(0, input_group)
            stopped_group = None
        elif not mirrored_input:
            last_attrs = current
            return False
        if foreground not in (input_group, shell_group):
            return False
        attrs = termios.tcgetattr(terminal)
        for index in (0, 3, 6):
            attrs[index] = current[index]
        attrs[1] = (original_attrs[1] & ~termios.OPOST
                    if current[1] & termios.OPOST else original_attrs[1])
        termios.tcsetattr(terminal, termios.TCSANOW, attrs)
        last_attrs = current
        mirrored_input = True
    return (input_group is not None and not current[3] & termios.ICANON
            and foreground == input_group)

try:
    resize()
    write_all(1, (slave_name + ' ' + token + '\n').encode())
    if not select.select([master], [], [], 5)[0] or os.read(master, 1) != b'\0':
        raise SystemExit(1)
    os.close(slave)
    slave = -1
    while True:
        resize()
        relay_keys = sync_input()
        ready = select.select([master, terminal] if relay_keys else [master], [], [], 0.1)[0]
        if terminal in ready:
            try:
                keys = os.read(terminal, 4096)
                if keys:
                    write_all(master, keys)
            except OSError as exc:
                if exc.errno != errno.EIO:
                    raise
        if master not in ready:
            continue
        try:
            data = os.read(master, 65536)
        except OSError as exc:
            if exc.errno == errno.EIO:
                break
            raise
        if not data:
            break
        consume(data)
    emit(pending)
    log_bytes(cleaner.feed(b'', final=True))
except (OSError, KeyboardInterrupt):
    pass  # Only a terminal failure ends display forwarding.
finally:
    if mirrored_input:
        try:
            if os.tcgetpgrp(terminal) in (input_group, shell_group):
                attrs = termios.tcgetattr(terminal)
                for index in (0, 1, 3, 6):
                    attrs[index] = original_attrs[index]
                termios.tcsetattr(terminal, termios.TCSANOW, attrs)
        except OSError:
            pass
    if slave >= 0:
        os.close(slave)
    os.close(master)
    os.close(terminal)
    for fd in (log_fd, state_fd):
        if fd is not None:
            os.close(fd)
    acknowledge()
TLOGGER_PY
}

# Decide whether a REPL-style command is being launched interactively. Args
# that run something (a script path, -c, -m for python; -e/--execute/--eval
# for a database client) mean it runs and exits, so its output belongs in
# the log; bare, or with only options, it is an interactive prompt to skip.
_tlogger_repl_is_interactive() {
  local _r="\$1"; shift
  local _a
  case "\$_r" in
    python|python2|python3|ipython|node)
      for _a in "\$@"; do
        case "\$_a" in
          -c|-m) return 1 ;;
          -i) return 0 ;;
          --) ;;
          -*) ;;
          *) return 1 ;;
        esac
      done
      return 0 ;;
    mysql|psql|mariadb|mongo|mongosh)
      for _a in "\$@"; do
        case "\$_a" in
          -e|--execute|--eval|-e*) return 1 ;;
        esac
      done
      return 0 ;;
    redis-cli|irb|pry)
      for _a in "\$@"; do
        [[ "\$_a" == -e || "\$_a" == --eval ]] && return 1
        [[ "\$_a" != -* ]] && return 1
      done
      return 0 ;;
    *) return 0 ;;
  esac
}

autoload -Uz add-zsh-hook
# Put it at the front rather than appending: a prompt plugin loaded earlier
# would otherwise run while the previous command's capture is still open.
# Assigning the array also makes a second source of this file idempotent.
precmd_functions=(tlogger_capture_exit \${precmd_functions:#tlogger_capture_exit})


# Empty unless the pty block below is installed, which is what fills it in.
TLOGGER_PTY_CMDS=()

# Skipped entirely: these run straight against the terminal and are not
# recorded, because piping them through tee breaks their rendering.
TLOGGER_INTERACTIVE_CMDS=(
  vim vi nvim nano emacs
  less more man
  fzf
  htop top btop
  tmux screen
  ssh telnet ftp
  smbclient evil-winrm
  msfconsole
  ligolo-proxy ligolo-agent ligolo-ng ligolo-mp ligolo-mp-client
  impacket-psexec impacket-smbexec impacket-wmiexec impacket-atexec
  impacket-dcomexec impacket-mssqlclient impacket-smbclient
  rlwrap gdb r2 radare2
  sqlmap
  nc ncat netcat pwncat
)

# REPL-style tools that are a full-screen prompt when launched bare, but run
# and exit non-interactively when given a script/query/-c/-m/-e. Skipping
# them unconditionally on the name alone drops the output that matters -
# "python3 exploit.py", "python3 -m http.server", "mysql -e '...'". They are
# skipped only when actually interactive; otherwise they go into the log.
TLOGGER_REPL_CMDS=(
  python3 python python2 ipython
  mysql psql mariadb mongo mongosh redis-cli
  irb pry node
)


tlogger_start() {
  setopt local_options no_err_exit unset
  [[ -n "\$TLOGGER_ACTIVE" ]] && return
  local _dir="\$HOME/Desktop/logs"
  if ! mkdir -p "\$_dir" 2>/dev/null || [[ ! -d "\$_dir" ]]; then
    echo "[tlogger] cannot create \$_dir — logging NOT started" >&2
    return 1
  fi
  # The pid keeps two terminals opened in the same second apart; without it
  # they share a file and their commands interleave.
  local _log="\$_dir/session_\$(date -u +%Y%m%d_%H%M%S)_\$\$_UTC.log"
  if [[ -L "\$_log" ]]; then
    echo "[tlogger] \$_log is a symlink; refusing to write through it" >&2
    return 1
  fi
  # 600: the log holds every command and its output, credentials included.
  if ! ( umask 077; : >> "\$_log" ) 2>/dev/null || [[ ! -w "\$_log" ]]; then
    echo "[tlogger] cannot write \$_log — logging NOT started" >&2
    return 1
  fi
  local _state
  _state="\$(mktemp "\$_dir/.tlogger-state.\$\$.XXXXXX")" || return 1
  print -rn -- 1 >| "\$_state"
  export TLOGGER_STATE="\$_state" TLOGGER_STATE_OWNER=\$\$
  unset TLOGGER_PAUSED
  export TLOGGER_LOG="\$_log"
  export TLOGGER_ACTIVE=1
  echo "[+] Logging started"
  echo "[+] Log file: \$TLOGGER_LOG"
  (( \${+functions[_tlogger_recover_orphans]} )) && _tlogger_recover_orphans
  # Explicit: the line above is false in a build without pty capture, and
  # its status would otherwise become the function's, so a successful start
  # would look like a failure to the caller.
  return 0
}

tlogger_stop() {
  setopt local_options no_err_exit unset
  [[ -z "\$TLOGGER_ACTIVE" ]] && return
  unset TLOGGER_ACTIVE
  # Without this the pending exit line is printed by the next precmd, when
  # stdout has already been handed back, so it lands on the screen.
  unset TLOGGER_LAST_LOGGED TLOGGER_LAST_PIPED
  export TLOGGER_PAUSED=1
  [[ -n "\${TLOGGER_OUTPUT_TOKEN:-}" ]] \
    && printf '\\033]tlogger-finish;%s\\007' "\$TLOGGER_OUTPUT_TOKEN" 2>/dev/null
  exec >/dev/tty 2>&1
  _tlogger_finish_output
  _tlogger_disable_state
  echo "[+] Logging stopped"
}

tlogger_status() {
  setopt local_options no_err_exit unset
  local _mode="manual"
  [[ "\$TLOGGER_AUTOSTART" -eq 1 ]] && _mode="automatic"
  if [[ -n "\$TLOGGER_ACTIVE" ]]; then
    local _size="?"
    [[ -f "\$TLOGGER_LOG" ]] && _size=\$(du -h "\$TLOGGER_LOG" 2>/dev/null | awk '{print \$1}')
    echo "[tlogger] ACTIVE  (mode: \$_mode)"
    echo "  log:  \$TLOGGER_LOG"
    echo "  size: \$_size"
  else
    echo "[tlogger] STOPPED (mode: \$_mode)"
  fi
}

tlogger_note() {
  setopt local_options no_err_exit unset
  if [[ -z "\$*" ]]; then
    echo "usage: tlogger_note <message>"
    return 1
  fi
  if [[ -z "\$TLOGGER_ACTIVE" ]]; then
    echo "[tlogger] not active — note not saved (run tlogger_start first)"
    return 1
  fi
  # While a command is being captured, stdout is that capture. Writing the
  # marker there keeps it in step with output produced earlier on the same
  # line; writing to the file directly would overtake the buffered stream.
  if [[ -n "\${TLOGGER_LAST_PIPED:-}" ]]; then
    printf "\\n### NOTE [%s] %s ###\\n" \
      "\$(TZ=UTC date '+%Y-%m-%d %H:%M:%S UTC')" "\$*"
    return 0
  fi
  if ! printf "\\n### NOTE [%s] %s ###\\n" \
       "\$(TZ=UTC date '+%Y-%m-%d %H:%M:%S UTC')" "\$*" >> "\$TLOGGER_LOG" 2>/dev/null; then
    echo "[tlogger] could not write to \$TLOGGER_LOG — note NOT saved" >&2
    return 1
  fi
  echo "[+] Note saved"
}

tlogger_mode() {
  setopt local_options no_err_exit unset
  case "\$1" in
    auto|automatic)
      export TLOGGER_AUTOSTART=1
      echo "[tlogger] mode: automatic"
      ;;
    manual)
      export TLOGGER_AUTOSTART=0
      echo "[tlogger] mode: manual"
      ;;
    *)
      local _cur="manual"
      [[ "\$TLOGGER_AUTOSTART" -eq 1 ]] && _cur="automatic"
      echo "usage: tlogger_mode auto|manual  (current: \$_cur)"
      ;;
  esac
}


tlogger_grep() {
  setopt local_options no_err_exit unset
  if [[ -z "\$1" ]]; then
    echo "usage: tlogger_grep <pattern>"
    return 1
  fi
  setopt local_options null_glob
  local -a _logs
  _logs=("\$HOME"/Desktop/logs/session_*_UTC.log)
  if (( \${#_logs} == 0 )); then
    echo "[tlogger] no session logs yet"
    return 1
  fi
  grep -an --color=auto -H -- "\$@" "\${_logs[@]}" 2>/dev/null
}


tlogger_preexec() {
  [[ -n "\${TLOGGER_ACTIVE:-}" ]] || return
  # Isolate from the user's shell options: under errexit a non-zero test in
  # here would exit the whole shell, and nounset would abort on an unset var.
  setopt local_options no_err_exit unset
  if [[ ! -r "\${TLOGGER_STATE:-}" || "\$(<"\$TLOGGER_STATE")" != 1 ]]; then
    unset TLOGGER_ACTIVE TLOGGER_LAST_LOGGED TLOGGER_LAST_PIPED
    export TLOGGER_PAUSED=1
    _tlogger_disable_state
    return
  fi

  # Recreate the log at 600 if it went away: a plain append would bring it
  # back under the ambient umask, usually world-readable.
  [[ -e "\$TLOGGER_LOG" ]] || ( umask 077; : >> "\$TLOGGER_LOG" ) 2>/dev/null

  # Two different failures, both of which must stop logging with one message
  # and no leaked error:
  #  - the path is not writable (deleted log directory, bad path). Test for it
  #    first, because a failed ">>" prints its open error before 2>/dev/null
  #    can apply and one line would reach the terminal.
  #  - the path is writable but the write itself fails (a full disk: /dev/full
  #    opens fine, ENOSPC only on write). Detect that from the write's status.
  _tlogger_stopped() {
    _tlogger_disable_state
    unset TLOGGER_ACTIVE TLOGGER_LAST_LOGGED TLOGGER_LAST_PIPED
    export TLOGGER_PAUSED=1
    echo "[tlogger] cannot write \${TLOGGER_LOG:-the log} - logging stopped." >&2
    echo "[tlogger] free some space or fix the path, then run tlogger_start." >&2
  }

  if [[ ! -w "\$TLOGGER_LOG" ]]; then
    _tlogger_stopped
    return
  fi

  if ! {
    printf "\\n┌──(%s㉿%s)-[%s] [%s] [tun0:%s]\\n" \
      "\$USER" "\$HOST" "\${PWD/#\$HOME/~}" \
      "\$(TZ=UTC date '+%Y-%m-%d %H:%M:%S UTC')" \
      "\$(tun0_ip)"
    printf "└─$ %s\\n" "\$1"
  } >> "\$TLOGGER_LOG" 2>/dev/null; then
    _tlogger_stopped
    return
  fi

  TLOGGER_LAST_LOGGED=1

  # Only a bare invocation is exempt from capture. In a pipeline or list the
  # output belongs to the whole line, so it still goes through tee; the pty
  # wrapper stands down on its own there because stdout is no longer a tty.
  # (z) splits the way the shell does, so an operator inside quotes stays
  # part of its word: ssh host "a; b" is still a bare ssh invocation.
  local -a _tlogger_words
  _tlogger_words=(\${(z)1})

  local _tlogger_bare=1 _tlogger_w
  for _tlogger_w in "\$_tlogger_words[@]"; do
    case "\$_tlogger_w" in
      '|'|'||'|'&'|'&&'|';'|'<'|'>'|'>>'|'<<'|'|&'|'&>'|[0-9]'>'|[0-9]'>>')
        _tlogger_bare=0
        break
        ;;
    esac
  done

  # Look past wrappers, their options and assignments - "sudo -u kali vim",
  # "env -i PATH=/usr/bin vim" - and compare the basename, so /usr/bin/vim
  # is recognised as vim.
  local _tlogger_first="\${_tlogger_words[1]}"
  # Declared once: re-running local on a name that already holds a value
  # makes zsh print it, so declaring inside the loop leaked
  # _tlogger_optarg=... onto the terminal for every prefixed command.
  local _tlogger_wrap _tlogger_optarg
  while (( \${#_tlogger_words} )); do
    # Test for an assignment on the raw word: :t on PATH=/usr/bin would
    # leave "bin" and the assignment would no longer be recognised.
    if [[ "\${_tlogger_words[1]}" == *=* ]]; then
      shift _tlogger_words
      continue
    fi
    _tlogger_wrap="\${_tlogger_words[1]:t}"
    _tlogger_optarg=''
    case "\$_tlogger_wrap" in
      # Which options take a separate value depends on the wrapper: nice -n
      # consumes a number, while sudo -n is a flag on its own.
      sudo|doas) _tlogger_optarg='-u -g -U -C -p -r -t -h -R' ;;
      proxychains|proxychains4) _tlogger_optarg='-f' ;;
      env)       _tlogger_optarg='-u -C -S' ;;
      nice)      _tlogger_optarg='-n' ;;
      command|nohup|time|stdbuf) _tlogger_optarg='' ;;
      *) break ;;
    esac
    shift _tlogger_words
    while (( \${#_tlogger_words} )) && [[ "\${_tlogger_words[1]}" == -* ]]; do
      if [[ -n "\$_tlogger_optarg" && " \$_tlogger_optarg " == *" \${_tlogger_words[1]} "* ]]; then
        shift _tlogger_words
        (( \${#_tlogger_words} )) && [[ "\${_tlogger_words[1]}" != -* ]] \
          && shift _tlogger_words
      else
        shift _tlogger_words
      fi
    done
  done
  local _tlogger_cmd="\${_tlogger_words[1]:t}"

  if (( _tlogger_bare )); then
    # The pty wrapper is an alias, so it only fires when the name is the
    # first word. Through sudo/env or an absolute path it never runs, and
    # skipping the general capture too would drop the session silently.
    if (( \${TLOGGER_PTY_CMDS[(I)\$_tlogger_cmd]} )) \
       && [[ "\$_tlogger_first" != "\$_tlogger_cmd" ]]; then
      printf "[tlogger] session body not captured: %s ran via %s, which bypasses the pty wrapper\\n" \
        "\$_tlogger_cmd" "\$_tlogger_first" >> "\$TLOGGER_LOG"
    fi
    for _tlogger_ic in \$TLOGGER_INTERACTIVE_CMDS \$TLOGGER_PTY_CMDS; do
      [[ "\$_tlogger_cmd" == "\$_tlogger_ic" ]] && return
    done
    # A REPL is skipped only when launched as an interactive prompt; given a
    # script or a one-shot query it falls through and its output is logged.
    if (( \${TLOGGER_REPL_CMDS[(I)\$_tlogger_cmd]} )) \
       && _tlogger_repl_is_interactive "\$_tlogger_cmd" "\${(@)_tlogger_words[2,-1]}"; then
      return
    fi
  fi

  TLOGGER_LAST_PIPED=1
  # An output-only pty preserves automatic colour and foreground job control.
  # Explicit command redirects/pipelines still override these descriptors.
  local _tlogger_slave
  if command -v python3 >/dev/null 2>&1 \
     && exec {TLOGGER_OUTPUT_FD}< <(
       # Detach the relay: zsh otherwise waits for this process substitution
       # to finish before read returns, while the relay waits for our open.
       _tlogger_output_pty &!
     ) && IFS=' ' read -r -t 3 -u "\$TLOGGER_OUTPUT_FD" _tlogger_slave TLOGGER_OUTPUT_TOKEN \
     && [[ "\$_tlogger_slave" == /dev/pts/<-> || "\$_tlogger_slave" == /proc/<->/fd/<-> ]]; then
    if exec > "\$_tlogger_slave" 2>&1; then
      printf '\\0'
      return
    fi
  fi
  _tlogger_finish_output
  _tlogger_stopped
  echo '[tlogger] output relay unavailable; this command runs without recording.' >&2
}

tlogger_precmd() {
  setopt local_options no_err_exit unset
  if [[ "\${TLOGGER_AUTOSTART:-0}" -eq 1 && -z "\${TLOGGER_ACTIVE:-}" && -z "\${TLOGGER_PAUSED:-}" ]]; then
    # A failure here would otherwise be retried, and reported, before every
    # single prompt for the rest of the session.
    tlogger_start || {
      export TLOGGER_PAUSED=1
      echo "[tlogger] autostart disabled for this shell; fix the above and run tlogger_start" >&2
    }
  fi
}

add-zsh-hook preexec tlogger_preexec
add-zsh-hook precmd tlogger_precmd
add-zsh-hook zshexit _tlogger_exit_state

### TLOGGER FINAL CLEAN END ###

EOF

  (( WANT_PTY )) && write_pty_block

  if [ "$THEME_DETECTED" -eq 1 ]; then
    echo -e "${CYAN}[i] A prompt framework was detected in your .zshrc.${RESET}"
    echo -e "    TLOGGER leaves your prompt alone — it will look exactly as it did"
    echo -e "    before. Every log entry still records user, host, cwd, UTC time and"
    echo -e "    the tun0 address in its header, so nothing is missing from the log."
    echo -e "    To also see the VPN address on screen, add it as a segment in your"
    echo -e "    own theme's configuration."
    echo
  fi

  print_usage
  print_reload_hint
}

uninstall() {
  if grep -q "### TLOGGER FINAL CLEAN START ###" "$ZSHRC" 2>/dev/null; then
    sed -i.tlogger_uninstall_bak \
      -e '/### TLOGGER FINAL CLEAN START ###/,/### TLOGGER FINAL CLEAN END ###/d' \
      -e '/### TLOGGER PTY CAPTURE ###/,/### TLOGGER PTY CAPTURE END ###/d' "$ZSHRC"
    echo -e "${GREEN}[✓] TLOGGER uninstalled (only the TLOGGER block was removed, other .zshrc edits kept)${RESET}"
    echo -e "${CYAN}    Safety copy of the pre-uninstall .zshrc: ${ZSHRC}.tlogger_uninstall_bak${RESET}"
  else
    echo -e "${YELLOW}[i] TLOGGER block not found in ${ZSHRC} — nothing to uninstall${RESET}"
  fi
}

case "$ACTION" in
  install) install ;;
  uninstall) uninstall ;;
  *) print_usage ;;
esac
