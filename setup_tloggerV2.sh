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
  tlogger_pty add <cmd>       capture an interactive command through a pty

Logs:
  ~/Desktop/logs/session_<UTC_TIMESTAMP>_UTC.log

USAGE
}

print_reload_hint() {
  echo -e "${YELLOW}[!] This shell was started before the install, so the tlogger${RESET}"
  echo -e "${YELLOW}    commands are not defined in it yet. Start a new terminal, or:${RESET}"
  echo -e "${GREEN}      exec zsh${RESET}"
  echo
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
  # Everything a command produced must be closed out, and stdout handed
  # back, before any other precmd hook runs - otherwise a prompt plugin
  # that prints gets recorded as if the command had produced it.
  if [[ -n "\${TLOGGER_LAST_LOGGED:-}" && -n "\${TLOGGER_LOG:-}" ]]; then
    if [[ -n "\${TLOGGER_LAST_PIPED:-}" ]]; then
      printf "[exit:%d]\\n" "\$TLOGGER_LAST_EXIT"
    else
      printf "[exit:%d]\\n" "\$TLOGGER_LAST_EXIT" >> "\$TLOGGER_LOG"
    fi
    unset TLOGGER_LAST_LOGGED TLOGGER_LAST_PIPED
  fi
  [[ -n "\${TLOGGER_ACTIVE:-}" ]] && exec >/dev/tty 2>&1
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

autoload -Uz add-zsh-hook
# Put it at the front rather than appending: a prompt plugin loaded earlier
# would otherwise run while the previous command's capture is still open.
# Assigning the array also makes a second source of this file idempotent.
precmd_functions=(tlogger_capture_exit \${precmd_functions:#tlogger_capture_exit})

# Captured through a real pty via script(1): the session renders normally
# on screen AND the full transcript goes into the log.
# Add any interactive command you want recorded, e.g. (ssh msfconsole mysql)
TLOGGER_PTY_CMDS=(ssh)

# Skipped entirely: these run straight against the terminal and are not
# recorded, because piping them through tee breaks their rendering.
# Move a command from here into TLOGGER_PTY_CMDS to record it instead.
TLOGGER_INTERACTIVE_CMDS=(
  vim vi nvim nano emacs
  less more man
  fzf
  htop top btop
  tmux screen
  ssh telnet ftp
  smbclient evil-winrm
  msfconsole
  mysql psql mongo redis-cli
  python3 python python2 ipython
  irb pry
  sqlmap
  nc ncat netcat
)

# A pty capture is only merged into the log once the command finishes, so a
# terminal killed mid-command leaves its transcript stranded in the temp
# file. Pick up anything left behind by a shell that is no longer running.
_tlogger_recover_orphans() {
  setopt local_options null_glob
  local _f _pid _claim
  for _f in "\${TMPDIR:-/tmp}"/tlogger_pty.*(.N); do
    [[ "\$_f" == *.claimed.* ]] && continue
    _pid="\${\${_f:t}#tlogger_pty.}"
    _pid="\${_pid%%.*}"
    [[ "\$_pid" == <-> ]] || continue
    kill -0 "\$_pid" 2>/dev/null && continue

    # Claim by rename: whoever wins the rename owns the file, so two
    # terminals starting at once cannot both import the same transcript.
    _claim="\${_f}.claimed.\$\$"
    mv -- "\$_f" "\$_claim" 2>/dev/null || continue

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

tlogger_start() {
  [[ -n "\$TLOGGER_ACTIVE" ]] && return
  local _dir="\$HOME/Desktop/logs"
  if ! mkdir -p "\$_dir" 2>/dev/null || [[ ! -d "\$_dir" ]]; then
    echo "[tlogger] cannot create \$_dir — logging NOT started" >&2
    return 1
  fi
  # The pid keeps two terminals opened in the same second apart; without it
  # they share a file and their commands interleave.
  local _log="\$_dir/session_\$(date -u +%Y%m%d_%H%M%S)_\$\$_UTC.log"
  # 600: the log holds every command and its output, credentials included.
  if ! ( umask 077; : >> "\$_log" ) 2>/dev/null || [[ ! -w "\$_log" ]]; then
    echo "[tlogger] cannot write \$_log — logging NOT started" >&2
    return 1
  fi
  unset TLOGGER_PAUSED
  export TLOGGER_LOG="\$_log"
  export TLOGGER_ACTIVE=1
  echo "[+] Logging started"
  echo "[+] Log file: \$TLOGGER_LOG"
  _tlogger_recover_orphans
}

tlogger_stop() {
  [[ -z "\$TLOGGER_ACTIVE" ]] && return
  unset TLOGGER_ACTIVE
  # Without this the pending exit line is printed by the next precmd, when
  # stdout has already been handed back, so it lands on the screen.
  unset TLOGGER_LAST_LOGGED TLOGGER_LAST_PIPED
  export TLOGGER_PAUSED=1
  exec >/dev/tty 2>&1
  echo "[+] Logging stopped"
}

tlogger_status() {
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

# Apply this shell's additions and removals to whatever is on disk now,
# under a lock, so two terminals editing the list do not overwrite each
# other with their own stale copy.
_tlogger_persist_pty_cmds() {
  local -a _added=("\${(@P)1}") _removed=("\${(@P)2}")
  # :A resolves symlinks - editing the link itself would replace it with a
  # regular file and orphan the dotfile it points at.
  local _zshrc="\$HOME/.zshrc"
  _zshrc="\${_zshrc:A}"
  [[ -f "\$_zshrc" ]] || return 1
  grep -q '^TLOGGER_PTY_CMDS=(' "\$_zshrc" || return 1

  local _lock="\${_zshrc}.tlogger.lock" _tries=0 _owner
  while ! mkdir "\$_lock" 2>/dev/null; do
    # A shell killed while holding the lock would otherwise block every
    # later save for good, so take it over once its owner is gone.
    _owner=\$(cat "\$_lock/pid" 2>/dev/null)
    if [[ -z "\$_owner" ]] || ! kill -0 "\$_owner" 2>/dev/null; then
      rm -rf "\$_lock" 2>/dev/null
      continue
    fi
    (( ++_tries > 30 )) && { echo "[tlogger] config is locked by pid \$_owner; not saved" >&2; return 1; }
    sleep 0.1
  done
  echo \$\$ > "\$_lock/pid" 2>/dev/null

  {
    local _line _disk
    _line=\$(grep -m1 '^TLOGGER_PTY_CMDS=(' "\$_zshrc")
    # The parentheses have to be escaped: unquoted they are read as glob
    # grouping and zsh rejects the pattern outright.
    _disk="\${_line#*\\(}"
    _disk="\${_disk%\\)*}"
    local -a _list=(\${=_disk}) _c
    for _c in "\$_added[@]"; do
      (( \${_list[(I)\$_c]} )) || _list+=("\$_c")
    done
    for _c in "\$_removed[@]"; do
      _list=("\${(@)_list:#\$_c}")
    done

    local _tmp="\${_zshrc}.tlogger.new"
    if sed "s|^TLOGGER_PTY_CMDS=(.*)\$|TLOGGER_PTY_CMDS=(\${_list})|" "\$_zshrc" > "\$_tmp" \
       && zsh -n "\$_tmp" 2>/dev/null; then
      cat "\$_tmp" > "\$_zshrc" && echo "[tlogger] saved — other terminals pick this up on restart"
      rm -f "\$_tmp"
    else
      rm -f "\$_tmp"
      echo "[tlogger] refusing to write an unparsable .zshrc; nothing saved" >&2
      return 1
    fi
  } always {
    rm -rf "\$_lock" 2>/dev/null
  }
}

tlogger_pty() {
  local _c
  local -a _tlogger_added _tlogger_removed
  case "\$1" in
    add)
      shift
      [[ \$# -eq 0 ]] && { echo "usage: tlogger_pty add <cmd>..."; return 1; }
      for _c in "\$@"; do
        # The name is written into .zshrc, so anything outside a plain
        # command name could break the file on the next shell start.
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
        _tlogger_added+=("\$_c")
        _tlogger_pty_alias "\$_c"
        echo "[tlogger] \$_c is now captured through a pty"
        # script(1) owns the pty, so Ctrl-Z stops inside it instead of
        # handing the shell back. It matters most for a caught shell, where
        # Ctrl-Z then "stty raw -echo; fg" is the usual upgrade.
        echo "           note: Ctrl-Z will not suspend \$_c while it is captured"
      done
      (( \${#_tlogger_added} )) && _tlogger_persist_pty_cmds _tlogger_added _tlogger_removed
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
        _tlogger_removed+=("\$_c")
        if [[ -n "\${TLOGGER_PTY_ORIG[\$_c]:-}" ]]; then
          alias "\$_c"="\${TLOGGER_PTY_ORIG[\$_c]}"
          unset "TLOGGER_PTY_ORIG[\$_c]"
        else
          unalias "\$_c" 2>/dev/null
        fi
        echo "[tlogger] \$_c is no longer captured"
      done
      (( \${#_tlogger_removed} )) && _tlogger_persist_pty_cmds _tlogger_added _tlogger_removed
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

tlogger_grep() {
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
  local _tlogger_rc=0
  {
    # -f flushes after every write: without it the transcript can still be
    # sitting in a buffer when the terminal is killed, leaving nothing to
    # recover even though the screen showed the output.
    script -qef -c "\$_tlogger_real \${(j: :)\${(qq)@}}" "\$_tlogger_tmp"
    _tlogger_rc=\$?
    [[ -s "\$_tlogger_tmp" ]] && _tlogger_clean_ansi < "\$_tlogger_tmp" >> "\$TLOGGER_LOG"
  } always {
    rm -f "\$_tlogger_tmp"
  }
  return \$_tlogger_rc
}

for _tlogger_pc in \$TLOGGER_PTY_CMDS; do
  _tlogger_pty_alias "\$_tlogger_pc"
done
unset _tlogger_pc
_tlogger_pty_sync

tlogger_preexec() {
  [[ -n "\${TLOGGER_ACTIVE:-}" ]] || return

  # Recreate the log at 600 if it went away: a plain append would bring it
  # back under the ambient umask, usually world-readable.
  [[ -e "\$TLOGGER_LOG" ]] || ( umask 077; : >> "\$TLOGGER_LOG" ) 2>/dev/null

  {
    printf "\\n┌──(%s㉿%s)-[%s] [%s] [tun0:%s]\\n" \
      "\$USER" "\$HOST" "\${PWD/#\$HOME/~}" \
      "\$(TZ=UTC date '+%Y-%m-%d %H:%M:%S UTC')" \
      "\$(tun0_ip)"
    printf "└─$ %s\\n" "\$1"
  } >> "\$TLOGGER_LOG"

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
  while (( \${#_tlogger_words} )); do
    # Test for an assignment on the raw word: :t on PATH=/usr/bin would
    # leave "bin" and the assignment would no longer be recognised.
    if [[ "\${_tlogger_words[1]}" == *=* ]]; then
      shift _tlogger_words
      continue
    fi
    local _tlogger_wrap="\${_tlogger_words[1]:t}" _tlogger_optarg
    case "\$_tlogger_wrap" in
      # Which options take a separate value depends on the wrapper: nice -n
      # consumes a number, while sudo -n is a flag on its own.
      sudo|doas) _tlogger_optarg='-u -g -U -C -p -r -t -h -R' ;;
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
  fi

  TLOGGER_LAST_PIPED=1
  exec > >(
    tee >( _tlogger_clean_ansi >> "\$TLOGGER_LOG" )
  ) 2>&1
}

tlogger_precmd() {
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

### TLOGGER FINAL CLEAN END ###

EOF

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
    sed -i.tlogger_uninstall_bak '/### TLOGGER FINAL CLEAN START ###/,/### TLOGGER FINAL CLEAN END ###/d' "$ZSHRC"
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

