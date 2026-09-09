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

Logs are written to `~/Desktop/logs/session_<UTC_TIMESTAMP>_UTC.log`. Each command entry also records its exit code (`[exit:N]`).

## Design notes / known limitations

- **Interactive/TUI tools are not captured.** Commands like `vim`, `ssh`, `msfconsole`, `tmux`, `mysql`, etc. (see `TLOGGER_INTERACTIVE_CMDS` in the script) bypass logging entirely and run directly against the real terminal. This is intentional: the logging mechanism uses `exec > >(tee ...)`, which doesn't allocate a real pty, so curses/full-screen apps would render incorrectly or have their output buffered/delayed if captured. The header line (command + timestamp) is still logged; the interactive session itself is not. Take screenshots for those.
- The regex used to strip ANSI escape codes from captured output is reasonably thorough but not a full terminal-sequence parser; a small number of exotic escape sequences may leak through.
- Log files contain everything you type and everything captured commands print, in cleartext — including credentials passed on the command line. Treat log files as sensitive.

## License

MIT — see [LICENSE](LICENSE). Credit to Salar and Ph03n1x for the original tool.
