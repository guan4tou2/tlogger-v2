# tlogger-v2

A zsh terminal session logger built for OSCP / penetration testing exam documentation. Every command you run — with a timestamp, working directory, and your VPN (`tun0`) IP — gets written to a clean, timestamped log file, so you can rebuild your attack timeline when writing the report instead of relying on memory or screenshots.

**Target environment: Kali Linux.** It assumes zsh, Python 3 (standard library only), GNU sed, iproute2 (`ip`), and a `tun0` VPN interface — i.e. a stock Kali exam/lab box.

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

### Reverse shells and the exam

For OSCP the reverse-shell session is where the flags are, so whether it lands in the log matters. The defaults reflect one specific tradeoff that `script` cannot avoid:

- **`socat` and `pwncat-cs` are captured by default.** They set up their own TTY, so capturing them through `script` is lossless — the remote prompt, `id`, and `cat proof.txt` all reach the log. `socat` records cleanly; `pwncat-cs` works too, but its status bar redraws leave repeated `bound to ...` fragments in the log around the actual output (the same redraw noise a fancy remote prompt produces).
- **`nc`/`ncat`/`pwncat` stay native and are *not* logged.** A captured command cannot be suspended (see below), and the `nc` shell upgrade — `Ctrl-Z`, then `stty raw -echo; fg` — needs exactly that. Keeping `nc` native preserves the upgrade; the cost is that an `nc` reverse shell is not in the log, so screenshot those flags (OSCP wants the screenshot anyway).

If you catch shells with `nc` and still want them logged, `tlogger_pty add nc` — but then the `Ctrl-Z` upgrade will not work in that session. Prefer `socat`/`pwncat-cs` if you want both.

Anything on that list gets an alias routing it through `script`, so it keeps a real terminal while its transcript is cleaned and appended to the log. Good candidates are shells and REPL-style tools whose scrollback is worth keeping: `msfconsole`, `ligolo-proxy`, `mysql`, `psql`, `evil-winrm`, `nc`. The pivoting and impacket consoles are on the skip list by default, so they work but are not recorded; move the ones whose transcript you want into `TLOGGER_PTY_CMDS`.

Editors and pagers are deliberately left in the skip list: capturing `vim` mostly records screen redraws, not content.

**REPL tools are captured when they run something.** `python`, `ipython`, `mysql`, `psql`, `redis-cli`, `irb`, `pry`, `node` are a full-screen prompt when launched bare (skipped, so they keep their terminal), but `python3 exploit.py`, `python3 -m http.server`, `python3 -c '...'` and `mysql -e '...'` run and exit — their output is evidence, so those forms go into the log. The distinction is made from the arguments (a script, `-c`, `-m`, `-e`), and it holds through `sudo`, `env`, an absolute path and `proxychains`.

The wrapper stands down by itself when it would get in the way — when logging is off, when the command is in a pipeline or has its input or output redirected, or when `script` isn't installed — and falls through to running the command untouched.

### Keeping terminal colours

Ordinary recorded commands keep a terminal on stdout and stderr, including its window size. This preserves automatic colour in tools such as Kali's `ls` alias, `grep --color=auto`, and Git. The screen receives the original bytes; only the log copy has ANSI codes removed. Existing aliases, colour settings, and `NO_COLOR` are left alone: a tool that normally needs a colour flag still needs that flag.

This relay uses Python 3 and keeps ordinary stdin and job control on the original terminal. Jobs can still use `Ctrl-Z`, `fg`, and `Ctrl-C`; they are not launched inside another shell. An implicit pager such as Git's `less` may open the output terminal for keyboard input: when it requests raw/cbreak mode, the relay forwards those keys and restores terminal settings on exit. Interactive tools retain their existing skip/capture policy.

Explicit redirection still produces ordinary files, and an upstream command in a pipeline still sees a pipe. For example, `ls --color=auto > files.txt` and `ls --color=auto | cat` do not gain unwanted colour codes.

Set `TLOGGER_COLOR=0` to give commands pipe output instead, or `unset TLOGGER_COLOR` to restore terminal output. Both modes use the Python relay. If Python 3 or the relay is unavailable, recording pauses with a warning and the command runs directly on the terminal.

The relay writes cleaned output before acknowledging the end of a foreground command, so its body is saved before the next command header. If log writes fail, recording pauses while screen output continues. `tlogger_stop` revokes recording for every relay from that recording session, including background jobs, without terminating those jobs or hiding their output. Starting again does not re-enable old relays. A private state file coordinates this and is removed on stop or normal shell exit. Asynchronous background output can still interleave with later commands while recording is active; redirect long-running jobs to their own output files when attribution matters.

## Design notes / known limitations

- **SSH sessions are fully captured.** `ssh` runs under `script`, which gives it a real pty — the remote session renders normally on your screen *and* the whole transcript (remote prompt, commands, output) lands in the log. Passwords typed at an `ssh` password prompt are not captured, because terminal echo is off and only what's displayed gets recorded.
- **Other interactive/TUI tools are not captured.** `vim`, `msfconsole`, `tmux`, and interactive database prompts bypass logging and run directly against the original terminal. The header line and exit code are still logged; the session content is not. Full-screen redraws do not make a useful plain-text transcript. See "Recording more interactive tools" above if you want any of them captured.
- **Commands wrapped by `tlogger_pty` cannot be suspended back to the local shell with Ctrl-Z.** `script` owns their pty, so the stop signal is handled inside it and the local shell is not handed back. This restriction does not apply to the ordinary output relay or native skipped commands. Keep it in mind before putting `nc` on the `tlogger_pty` list: its `Ctrl-Z` then `stty raw -echo; fg` upgrade needs local job control. Commands run over `ssh` are unaffected — the remote shell handles suspension there.
- **A `tlogger_pty` capture is merged into the log when the command ends.** Close the terminal in the middle of one and the transcript is left in a temp file rather than the log. The next `tlogger_start` picks up anything left behind by a shell that is no longer running and appends it under a `### RECOVERED ###` marker. Ordinary output capture streams through the cleaner instead of using this transcript-recovery path.
- **Output from background jobs lands wherever it arrives.** The log is organised as one block per command, and a job started with `&` prints whenever it feels like it — usually under some later command's entry. The line is recorded, but its position in the file is not its position in time. Foreground work reads correctly; don't reconstruct a timeline from backgrounded output.
- **A nested shell writes to the same log.** Running `zsh` inside a logged session inherits the session's log rather than opening its own. The parent is blocked while the child runs, so nothing interleaves, and the commands did happen in that terminal — but the file will not tell you a subshell was involved.
- If the remote box you SSH into runs a heavily customized shell (autosuggestions, syntax highlighting, a multi-line prompt), its constant line redraws show up in the captured transcript as duplicated fragments. A plain `bash` prompt — which is what you usually land on after popping a shell — records cleanly.
- The regex used to strip ANSI escape codes from captured output is reasonably thorough but not a full terminal-sequence parser; a small number of exotic escape sequences may leak through.
- **`tlogger_start` takes effect from the next prompt, not the same line.** `tlogger_start; some_command` does not log `some_command`: the shell's pre-command hook for that whole line already ran, with logging off, before `tlogger_start` executed. Start logging, then run your commands on subsequent lines. Automatic mode sidesteps this entirely.
- **A hand-written `precmd()` that prints can leak into the log.** tlogger registers its hooks through `add-zsh-hook` and puts its own first, so every framework (oh-my-zsh, powerlevel10k, …) is handled. But a standalone `precmd() { ... }` you define yourself, if it prints, may run before tlogger hands stdout back and land in the previous command's entry. Use `add-zsh-hook precmd yourfunc` instead of a bare `precmd()` and it is ordered correctly.
- Log files contain everything you type and everything captured commands print, in cleartext — including credentials passed on the command line. Treat log files as sensitive.
- **A command's output can imitate tlogger's own markers.** Nothing distinguishes a `### NOTE ... ###` or `[exit:0]` line that tlogger wrote from one a command printed, so anything you run — including a program on a target box — can put convincing-looking markers into the log. It is your own record rather than tamper-evident evidence; if a specific line matters, keep the screenshot too.

## Tests

```bash
./tests/run_tests.sh
```

73 checks. Each installs into a throwaway `HOME` and drives a real interactive zsh through a pty, because the hooks do not fire under `zsh -c` and a piped stdout hides exactly the behaviour worth testing. Run it on Linux; the cleaner relies on GNU sed. Your own configuration is never touched.

They cover both install shapes, both modes, exit codes, UTF-8, notes, log permissions, stop, prompt-plugin isolation, wrapper prefixes and quoting, job control, binary output, one-log-per-terminal, an unwritable log directory, alias preservation and reloading, pty capture, interrupted-capture recovery, the installer's edge cases and uninstall. Set `TLOGGER_TEST_SETTLE` to give each command longer on a slow machine.

Additional real-terminal checks (require Python's `pexpect`, included on the tested Kali installation):

```bash
python3 tests/test_colour.py
python3 tests/test_kali_workflows.py
python3 tests/test_relay_lifecycle.py
```

The colour suite compares screen escape codes with logging off/on, plain-text logs, terminal dimensions, redirects, pipelines, job control, background output and descriptor cleanup. The Kali suite uses disposable loopback services for Nmap, curl, ffuf, Gobuster, feroxbuster, Python HTTP transfers, the `nc` shell upgrade and a `socat` shell, plus Vim/less interaction. It requires those tools to be installed. The lifecycle suite exercises file-size write failures, stop/restart with background output, delayed log writes, split ANSI/UTF-8 output, background pager input, and simultaneous orphan recovery. All three scripts validate the installed relay's Python syntax and report their temporary evidence directory; none changes your shell configuration. These tests do not validate Windows authentication, AD sessions, or tools absent from the machine.

## License

MIT — see [LICENSE](LICENSE). Credit to Salar and Ph03n1x for the original tool.
