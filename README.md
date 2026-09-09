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

Logs are written to `~/Desktop/logs/session_<UTC_TIMESTAMP>_UTC.log`. Each command entry also records its exit code (`[exit:N]`), and SSH sessions are captured in full — see below.

## Design notes / known limitations

- **SSH sessions are fully captured.** `ssh` is wrapped so it runs under `script`, which gives it a real pty — the remote session renders normally on your screen *and* the whole transcript (remote prompt, commands, output) lands in the log. Passwords typed at an `ssh` password prompt are not captured, because the terminal echo is off and only what's displayed gets recorded.
- **Other interactive/TUI tools are not captured.** `vim`, `msfconsole`, `tmux`, `mysql`, etc. (see `TLOGGER_INTERACTIVE_CMDS`) bypass logging and run directly against the real terminal. The general logging mechanism uses `exec > >(tee ...)`, which does not allocate a pty, so curses/full-screen apps would render incorrectly or have their output buffered if captured that way. The header line (command + timestamp) and exit code are still logged; the session content is not. Take screenshots for those. The same `script`-wrapper trick used for `ssh` could be extended to any of them — see the `ssh()` function in the script — but for editors and pagers the captured output is mostly screen-redraw noise, which is why it's opt-in per command rather than applied to the whole whitelist.
- If the remote box you SSH into runs a heavily customized shell (autosuggestions, syntax highlighting, a multi-line prompt), its constant line redraws show up in the captured transcript as duplicated fragments. A plain `bash` prompt — which is what you usually land on after popping a shell — records cleanly.
- The regex used to strip ANSI escape codes from captured output is reasonably thorough but not a full terminal-sequence parser; a small number of exotic escape sequences may leak through.
- Log files contain everything you type and everything captured commands print, in cleartext — including credentials passed on the command line. Treat log files as sensitive.

## License

MIT — see [LICENSE](LICENSE). Credit to Salar and Ph03n1x for the original tool.
