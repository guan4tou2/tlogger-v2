
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
  clear
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
  ./setup_tlogger.sh install

Uninstall:
  ./setup_tlogger.sh uninstall

Manual mode:
  tlogger_start
  tlogger_stop

Automatic mode:
  Logging starts automatically in every new terminal

Logs:
  ~/Desktop/logs/session_<UTC_TIMESTAMP>_UTC.log

USAGE
}

install() {
  flash_banner
  ask_mode
  mkdir -p "$LOGDIR"

  if [ ! -f "$BACKUP" ]; then
    cp "$ZSHRC" "$BACKUP"
  fi

  if grep -q "### TLOGGER FINAL CLEAN START ###" "$ZSHRC"; then
    print_usage
    exit 0
  fi

  cat >> "$ZSHRC" <<EOF

### TLOGGER FINAL CLEAN START ###

export DISABLE_AUTO_TITLE=true
setopt promptsubst
export TLOGGER_AUTOSTART=$AUTOSTART

tun0_ip() {
  ip -4 addr show tun0 2>/dev/null | awk '/inet /{print \$2}' | cut -d/ -f1
}

# Remember whatever prompt was already configured, so a theme is not
# clobbered while logging is off and can be handed back on stop.
TLOGGER_ORIG_PROMPT="\$PROMPT"

configure_prompt() {
  [[ -n "\$TLOGGER_ACTIVE" ]] || return
  PROMPT=\$'%F{blue}┌──%f(%F{red}%n%f㉿%F{green}%m%f)-[%F{cyan}%~%f] [%F{yellow}\$(TZ=UTC date "+%Y-%m-%d %H:%M:%S UTC")%f] [%F{magenta}tun0:\$(tun0_ip)%f]\\n%F{blue}└─%f$ '
}

tlogger_capture_exit() {
  TLOGGER_LAST_EXIT=\$?
}

_tlogger_clean_ansi() {
  LC_ALL=C sed -r \
    -e 's/\\x1B\\][^\\a]*\\a//g' \
    -e 's/\\x1B\\][^\\x1B]*\\x1B\\\\//g' \
    -e 's/\\x1B\\[[0-9;:?]*[@-~]//g' \
    -e 's/\\x1B[=>McD78EHZ]//g' \
    -e 's/\\r\$//' \
    -e '/^Script (started|done) on .*\\[.*\\]\$/d'
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
  export TLOGGER_LOG="\$HOME/Desktop/logs/session_\$(date -u +%Y%m%d_%H%M%S)_UTC.log"
  export TLOGGER_ACTIVE=1
  echo "[+] Logging started"
  echo "[+] Log file: \$TLOGGER_LOG"
}

tlogger_stop() {
  [[ -z "\$TLOGGER_ACTIVE" ]] && return
  unset TLOGGER_ACTIVE
  export TLOGGER_PAUSED=1
  [[ -n "\$TLOGGER_ORIG_PROMPT" ]] && PROMPT="\$TLOGGER_ORIG_PROMPT"
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

tlogger_grep() {
  if [[ -z "\$1" ]]; then
    echo "usage: tlogger_grep <pattern>"
    return 1
  fi
  grep -n --color=auto -H -- "\$@" "\$HOME"/Desktop/logs/session_*_UTC.log 2>/dev/null
}

_tlogger_pty_run() {
  local _tlogger_cmd="\$1"
  shift
  if [[ -z "\$TLOGGER_ACTIVE" ]] || [[ ! -t 0 ]] || [[ ! -t 1 ]] \
     || ! command -v script >/dev/null 2>&1; then
    command "\$_tlogger_cmd" "\$@"
    return \$?
  fi
  local _tlogger_tmp
  _tlogger_tmp="\$(mktemp -t tlogger_pty.XXXXXX)" || {
    command "\$_tlogger_cmd" "\$@"
    return \$?
  }
  local _tlogger_rc=0
  {
    script -qe -c "command \$_tlogger_cmd \${(j: :)\${(qq)@}}" "\$_tlogger_tmp"
    _tlogger_rc=\$?
    [[ -s "\$_tlogger_tmp" ]] && _tlogger_clean_ansi < "\$_tlogger_tmp" >> "\$TLOGGER_LOG"
  } always {
    rm -f "\$_tlogger_tmp"
  }
  return \$_tlogger_rc
}

for _tlogger_pc in \$TLOGGER_PTY_CMDS; do
  alias "\$_tlogger_pc"="_tlogger_pty_run \$_tlogger_pc"
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
  disown %+ 2>/dev/null
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
# after tlogger_precmd, so the prompt reflects logging state set this cycle
add-zsh-hook precmd configure_prompt

### TLOGGER FINAL CLEAN END ###

EOF

  print_usage
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

