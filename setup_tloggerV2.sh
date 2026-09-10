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

  if [ ! -f "$BACKUP" ]; then
    cp "$ZSHRC" "$BACKUP"
  fi

  if grep -q "### TLOGGER FINAL CLEAN START ###" "$ZSHRC"; then
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
add-zsh-hook precmd tlogger_capture_exit

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

tlogger_start() {
  [[ -n "\$TLOGGER_ACTIVE" ]] && return
  mkdir -p "\$HOME/Desktop/logs"
  unset TLOGGER_PAUSED
  # The pid keeps two terminals opened in the same second apart; without it
  # they share a file and their commands interleave.
  export TLOGGER_LOG="\$HOME/Desktop/logs/session_\$(date -u +%Y%m%d_%H%M%S)_\$\$_UTC.log"
  export TLOGGER_ACTIVE=1
  echo "[+] Logging started"
  echo "[+] Log file: \$TLOGGER_LOG"
}

tlogger_stop() {
  [[ -z "\$TLOGGER_ACTIVE" ]] && return
  unset TLOGGER_ACTIVE
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
  printf "\\n### NOTE [%s] %s ###\\n" "\$(TZ=UTC date '+%Y-%m-%d %H:%M:%S UTC')" "\$*" >> "\$TLOGGER_LOG"
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

_tlogger_persist_pty_cmds() {
  local _zshrc="\$HOME/.zshrc"
  [[ -f "\$_zshrc" ]] || return
  grep -q '^TLOGGER_PTY_CMDS=(' "\$_zshrc" || return
  sed -i "s|^TLOGGER_PTY_CMDS=(.*)\$|TLOGGER_PTY_CMDS=(\$TLOGGER_PTY_CMDS)|" "\$_zshrc" \
    && echo "[tlogger] saved — other open terminals pick this up on restart"
}

tlogger_pty() {
  local _c
  case "\$1" in
    add)
      shift
      [[ \$# -eq 0 ]] && { echo "usage: tlogger_pty add <cmd>..."; return 1; }
      for _c in "\$@"; do
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
        if ! command -v "\$_c" >/dev/null 2>&1 && [[ -z "\${aliases[\$_c]}" ]]; then
          echo "[tlogger] warning: \$_c was not found in PATH — adding anyway"
        fi
        TLOGGER_PTY_CMDS+=("\$_c")
        _tlogger_pty_alias "\$_c"
        echo "[tlogger] \$_c is now captured through a pty"
      done
      _tlogger_persist_pty_cmds
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
        if [[ -n "\${TLOGGER_PTY_ORIG[\$_c]}" ]]; then
          alias "\$_c"="\${TLOGGER_PTY_ORIG[\$_c]}"
          unset "TLOGGER_PTY_ORIG[\$_c]"
        else
          unalias "\$_c" 2>/dev/null
        fi
        echo "[tlogger] \$_c is no longer captured"
      done
      _tlogger_persist_pty_cmds
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
  grep -an --color=auto -H -- "\$@" "\$HOME"/Desktop/logs/session_*_UTC.log 2>/dev/null
}

# Taking over a command name would silently drop an alias the user already
# had - Kali ships "ls --color=auto" - so remember it and keep using it.
typeset -gA TLOGGER_PTY_ORIG

_tlogger_pty_alias() {
  local _c="\$1"
  [[ -n "\${aliases[\$_c]}" && -z "\${TLOGGER_PTY_ORIG[\$_c]}" ]] \
    && TLOGGER_PTY_ORIG[\$_c]="\${aliases[\$_c]}"
  alias "\$_c"="_tlogger_pty_run \$_c"
}

_tlogger_pty_run() {
  local _tlogger_cmd="\$1"
  shift
  local _tlogger_real="\${TLOGGER_PTY_ORIG[\$_tlogger_cmd]:-command \$_tlogger_cmd}"
  local -a _tlogger_argv
  _tlogger_argv=(\${(z)_tlogger_real})
  if [[ -z "\$TLOGGER_ACTIVE" ]] || [[ ! -t 0 ]] || [[ ! -t 1 ]] \
     || ! command -v script >/dev/null 2>&1; then
    "\${_tlogger_argv[@]}" "\$@"
    return \$?
  fi
  local _tlogger_tmp
  _tlogger_tmp="\$(mktemp -t tlogger_pty.XXXXXX)" || {
    "\${_tlogger_argv[@]}" "\$@"
    return \$?
  }
  local _tlogger_rc=0
  {
    script -qe -c "\$_tlogger_real \${(j: :)\${(qq)@}}" "\$_tlogger_tmp"
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

tlogger_preexec() {
  [[ -n "\$TLOGGER_ACTIVE" ]] || return

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
  local _tlogger_cmd="\${1%% *}"
  if [[ "\$1" != *[\\|\\;\\&\\<\\>]* ]]; then
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
  if [[ -n "\$TLOGGER_LAST_LOGGED" && -n "\$TLOGGER_LOG" ]]; then
    if [[ -n "\$TLOGGER_LAST_PIPED" ]]; then
      printf "[exit:%d]\\n" "\$TLOGGER_LAST_EXIT"
    else
      printf "[exit:%d]\\n" "\$TLOGGER_LAST_EXIT" >> "\$TLOGGER_LOG"
    fi
    unset TLOGGER_LAST_LOGGED TLOGGER_LAST_PIPED
  fi
  if [[ "\$TLOGGER_AUTOSTART" -eq 1 && -z "\$TLOGGER_ACTIVE" && -z "\$TLOGGER_PAUSED" ]]; then
    tlogger_start
  fi
  [[ -n "\$TLOGGER_ACTIVE" ]] || return
  exec >/dev/tty 2>&1
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

