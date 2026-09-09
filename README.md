# tlogger-v2

A zsh terminal session logger built for OSCP / penetration testing exam documentation. Every command you run — with a timestamp, working directory, and your VPN (`tun0`) IP — gets written to a clean, timestamped log file, so you can rebuild your attack timeline when writing the report instead of relying on memory or screenshots.

**Target environment: Kali Linux.** It assumes zsh, GNU sed, iproute2 (`ip`), and a `tun0` VPN interface — i.e. a stock Kali exam/lab box.

## Credits

- **Salar** — original creation, April 2022
- **Ph03n1x** ([blog post](https://ph03n1x.net/tlogger-on-steroids/)) — enhanced and extended, December 2025
- **[guan4tou2](https://github.com/guan4tou2)** — bug fixes, macOS compatibility patch, and new features, 2026

This repo is a fork/continuation of Ph03n1x's `tlogger-on-steroids`, published with his permission.

## Install

```bash
chmod +x setup_tloggerV2.sh
./setup_tloggerV2.sh install
```

You'll be asked to choose a mode:

- **Manual** — control logging yourself with `tlogger_start` / `tlogger_stop`
- **Automatic** — logging starts on every new terminal

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

Logs are written to `~/Desktop/logs/session_<UTC_TIMESTAMP>_UTC.log`. Each command entry also records its exit code (`[exit:N]`), and SSH sessions are captured in full — see below.

## Recording more interactive tools

Interactive programs are handled by two lists in the `.zshrc` block the installer writes:

```zsh
TLOGGER_PTY_CMDS=(ssh)          # captured through a real pty, session goes into the log
TLOGGER_INTERACTIVE_CMDS=(vim vi nvim nano ... )   # skipped, not recorded
```

Manage the first list from the shell — the change applies immediately and is written back to `.zshrc`:

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
- If the remote box you SSH into runs a heavily customized shell (autosuggestions, syntax highlighting, a multi-line prompt), its constant line redraws show up in the captured transcript as duplicated fragments. A plain `bash` prompt — which is what you usually land on after popping a shell — records cleanly.
- The regex used to strip ANSI escape codes from captured output is reasonably thorough but not a full terminal-sequence parser; a small number of exotic escape sequences may leak through.
- Log files contain everything you type and everything captured commands print, in cleartext — including credentials passed on the command line. Treat log files as sensitive.

## License

MIT — see [LICENSE](LICENSE). Credit to Salar and Ph03n1x for the original tool.
