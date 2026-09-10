# tlogger-v2

A zsh terminal session logger built for OSCP / penetration testing exam documentation. Every command you run — with a timestamp, working directory, and your VPN (`tun0`) IP — gets written to a clean, timestamped log file, so you can rebuild your attack timeline when writing the report instead of relying on memory or screenshots.

**Target environment: Kali Linux.** It assumes zsh, GNU sed, iproute2 (`ip`), and a `tun0` VPN interface — i.e. a stock Kali exam/lab box.

**zsh only.** The logger is built on zsh's `precmd`/`preexec` hooks and zsh parameter expansion, and installs into `~/.zshrc`. It does not work under bash or sh — a bash port would need `PROMPT_COMMAND` and `trap DEBUG` and a rewrite of the array handling. Kali has defaulted to zsh since 2020, so this is usually already the case; the installer checks and tells you if it isn't.

## Credits

- **Salar** — original creation, April 2022
- **Ph03n1x** ([blog post](https://ph03n1x.net/tlogger-on-steroids/)) — enhanced and extended, December 2025
- **[guan4tou2](https://github.com/guan4tou2)** — bug fixes, pty capture, and the rest of what is here, 2026

This repo is a fork/continuation of Ph03n1x's `tlogger-on-steroids`, published with his permission.

## Install

```bash
chmod +x setup_tloggerV2.sh
./setup_tloggerV2.sh install
```

You'll be asked two things.

Mode:

- **Manual** — control logging yourself with `tlogger_start` / `tlogger_stop`
- **Automatic** — logging starts on every new terminal

Whether to also install pty capture:

- **No** — command output only. About 190 fewer lines in your `.zshrc`, no `script(1)`, no temp files.
- **Yes** — adds `tlogger_pty` and records `ssh` sessions in full.

To uninstall (only removes the tlogger block from `.zshrc`, your other edits are kept):

```bash
./setup_tloggerV2.sh uninstall
```

## Commands

| Command | Description |
|---|---|
| `tlogger_start` | Start logging (manual mode) |
| `tlogger_stop` | Stop logging — durable even in automatic mode |
| `tlogger_status` | Show whether logging is active, current mode, log path, and file size |
| `tlogger_note "message"` | Insert a timestamped `### NOTE ... ###` marker into the current log |
| `tlogger_mode auto\|manual` | Switch mode at runtime, no reinstall needed |
| `tlogger_grep <pattern>` | Search across all session logs at once |
| `tlogger_pty [list\|add\|remove]` | Manage which commands are captured through a pty |

Logs are written to `~/Desktop/logs/session_<UTC_TIMESTAMP>_<PID>_UTC.log` — one file per terminal, so several open at once never write into the same log. Each command entry also records its exit code (`[exit:N]`), and SSH sessions are captured in full — see below.

## Recording more interactive tools

Interactive programs are handled by two lists in the `.zshrc` block the installer writes:

```zsh
TLOGGER_PTY_CMDS=(ssh)          # captured through a real pty, session goes into the log
TLOGGER_INTERACTIVE_CMDS=(vim vi nvim nano ... )   # skipped, not recorded
```

Manage the list from the shell. The change applies to that shell only — tlogger never rewrites your config while it is running, so edit the `TLOGGER_PTY_CMDS` line in `.zshrc` to make it permanent:

```console
$ tlogger_pty list
[tlogger] captured through a pty: ssh
$ tlogger_pty add msfconsole mysql
$ tlogger_pty remove mysql
```

Anything on that list gets an alias routing it through `script`, so it keeps a real terminal while its transcript is cleaned and appended to the log. Good candidates are shells and REPL-style tools whose scrollback is worth keeping: `msfconsole`, `mysql`, `psql`, `evil-winrm`, `nc`.

Editors and pagers are deliberately left in the skip list: capturing `vim` mostly records screen redraws, not content.

The wrapper stands down by itself when it would get in the way — when logging is off, when the command is in a pipeline or has its input or output redirected, or when `script` isn't installed — and falls through to running the command untouched.

### Commands that format themselves differently when piped

While logging is active, a captured command's stdout is a pipe rather than a terminal, so tools that check `isatty` change how they print: `ls` drops to a single column with no colour, `grep --color=auto` stops colourising, `git` skips its pager. The recorded *content* is complete either way — only the on-screen formatting differs.

If that bothers you for a command you look at all day, put it on the pty list and the formatting comes back, log included:

```console
$ tlogger_pty add ls
```

## Design notes / known limitations

- **SSH sessions are fully captured.** `ssh` runs under `script`, which gives it a real pty — the remote session renders normally on your screen *and* the whole transcript (remote prompt, commands, output) lands in the log. Passwords typed at an `ssh` password prompt are not captured, because terminal echo is off and only what's displayed gets recorded.
- **Other interactive/TUI tools are not captured.** `vim`, `msfconsole`, `tmux`, `mysql`, etc. (see `TLOGGER_INTERACTIVE_CMDS`) bypass logging and run directly against the real terminal. The general logging mechanism uses `exec > >(tee ...)`, which does not allocate a pty, so curses/full-screen apps would render incorrectly or have their output buffered if captured that way. The header line and exit code are still logged; the session content is not. See "Recording more interactive tools" above if you want any of them captured.
- **A captured command cannot be suspended with Ctrl-Z.** `script` owns the pty, so the stop signal is handled inside it and the shell is not handed back; the command still exits normally. This is why editors stay on the skip list, and it is worth remembering before putting a caught shell (`nc`, `socat`) on the pty list, where Ctrl-Z followed by `stty raw -echo; fg` is the usual way to upgrade the session. Commands run over `ssh` are unaffected — the remote shell handles suspension there.
- **A capture is merged into the log when the command ends.** Close the terminal in the middle of one and the transcript is left in a temp file rather than the log. The next `tlogger_start` picks up anything left behind by a shell that is no longer running and appends it under a `### RECOVERED ###` marker, so it reaches the log one session late rather than never.
- **Output from background jobs lands wherever it arrives.** The log is organised as one block per command, and a job started with `&` prints whenever it feels like it — usually under some later command's entry. The line is recorded, but its position in the file is not its position in time. Foreground work reads correctly; don't reconstruct a timeline from backgrounded output.
- **A nested shell writes to the same log.** Running `zsh` inside a logged session inherits the session's log rather than opening its own. The parent is blocked while the child runs, so nothing interleaves, and the commands did happen in that terminal — but the file will not tell you a subshell was involved.
- If the remote box you SSH into runs a heavily customized shell (autosuggestions, syntax highlighting, a multi-line prompt), its constant line redraws show up in the captured transcript as duplicated fragments. A plain `bash` prompt — which is what you usually land on after popping a shell — records cleanly.
- The regex used to strip ANSI escape codes from captured output is reasonably thorough but not a full terminal-sequence parser; a small number of exotic escape sequences may leak through.
- Log files contain everything you type and everything captured commands print, in cleartext — including credentials passed on the command line. Treat log files as sensitive.

## Tests

```bash
./tests/run_tests.sh
```

Each case installs into a throwaway `HOME` and drives a real interactive zsh through a pty, because the hooks do not fire under `zsh -c` and a piped stdout hides exactly the behaviour worth testing. Run it on Linux; the cleaner relies on GNU sed. Your own configuration is never touched.

## License

MIT — see [LICENSE](LICENSE). Credit to Salar and Ph03n1x for the original tool.
