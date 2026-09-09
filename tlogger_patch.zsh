### TLOGGER INTERACTIVE FIX ###
# Claude Code 的 Bash tool 裡 exec > >(tee ...) 會污染 stdout capture，跳過全部 hook
[[ -n "$CLAUDECODE" ]] && return 0

# Mac: 覆寫 tun0_ip（macOS 無 ip 指令）
tun0_ip() {
  if command -v ip &>/dev/null; then
    ip -4 addr show tun0 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1
  else
    ifconfig 2>/dev/null | awk '
      /^(utun|ppp)[0-9]/ { iface=1 }
      iface && /inet / { print $2; iface=0; exit }
    '
  fi
}

# 覆寫 tlogger_preexec：互動性指令跳過 output redirection
tlogger_preexec() {
  [[ -n "$TLOGGER_ACTIVE" ]] || return

  {
    printf "\n┌──(%s㉿%s)-[%s] [%s] [tun0:%s]\n" \
      "$USER" "$HOST" "${PWD/#$HOME/~}" \
      "$(TZ=UTC date '+%Y-%m-%d %H:%M:%S UTC')" \
      "$(tun0_ip)"
    printf "└─$ %s\n" "$1"
  } >> "$TLOGGER_LOG"

  local cmd="${1%% *}"
  local _interactive=(
    vim vi nvim nano emacs
    less more man
    fzf
    htop top btop
    ssh
    msfconsole
    mysql psql mongo redis-cli
    python3 python python2 ipython
    irb pry
    sqlmap
    nc ncat netcat
  )
  for ic in $_interactive; do
    [[ "$cmd" == "$ic" ]] && return
  done

  exec > >(
    tee >(
      sed -r \
        -e 's/\x1B\][^\a]*\a//g' \
        -e 's/\x1B\[[0-9;]*[a-zA-Z]//g' \
        >> "$TLOGGER_LOG"
    )
  ) 2>&1
}
### TLOGGER INTERACTIVE FIX END ###

### TLOGGER EXIT HOOK ###
# 終端關閉時自動停止 logging
_tlogger_exit() {
  [[ -n "$TLOGGER_ACTIVE" ]] || return
  exec >/dev/tty 2>&1
  unset TLOGGER_ACTIVE
}
add-zsh-hook zshexit _tlogger_exit
### TLOGGER EXIT HOOK END ###

### TLOGGER LOG PATH (Mac only) ###
# 覆寫 tlogger_start：log 指向 BugBounty repo 內的 logs/
# 動態解析：優先用 workspace_layout.sh，fallback 到舊路徑
_tlogger_layout_sh="${0:a:h}/workspace_layout.sh"
if [[ -f "$_tlogger_layout_sh" ]]; then
  eval "$("$_tlogger_layout_sh" --shell 2>/dev/null)" || true
fi
TLOGGER_REPO_LOGDIR="${LOGS_ROOT:-$HOME/Desktop/BugBounty/logs}"
tlogger_start() {
  [[ -n "$TLOGGER_ACTIVE" ]] && return
  mkdir -p "$TLOGGER_REPO_LOGDIR"
  export TLOGGER_LOG="$TLOGGER_REPO_LOGDIR/session_$(date -u +%Y%m%d_%H%M%S)_UTC.log"
  export TLOGGER_ACTIVE=1
  echo "[+] Logging started"
  echo "[+] Log file: $TLOGGER_LOG"
}
### TLOGGER LOG PATH END ###

### TLOGGER PROMPT FIX ###
# configure_prompt 原本無條件覆蓋 PROMPT，衝突 p10k
# 改為：只在 TLOGGER_ACTIVE 時才接管 prompt；否則還給 p10k
configure_prompt() {
  [[ -n "$TLOGGER_ACTIVE" ]] || return
  PROMPT=$'%F{blue}┌──%f(%F{red}%n%f㉿%F{green}%m%f)-[%F{cyan}%~%f] [%F{yellow}'"$(TZ=UTC date '+%Y-%m-%d %H:%M:%S UTC')"$'%f] [%F{magenta}tun0:'"$(tun0_ip)"$'%f]\n%F{blue}└─%f$ '
}
### TLOGGER PROMPT FIX END ###
