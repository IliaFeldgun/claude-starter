---
name: clipboard
description: Push text to the user's host (Mac) clipboard from inside this container, so they can paste it instead of retyping. Use whenever you want the user to run a shell command, paste a token/URL/snippet, or copy any output you produce — e.g. "here's the command to run", "copy this", "put X on my clipboard", "I can't select that", "clip me", "let me run". Works via an OSC 52 escape written to the terminal pty; no host setup required.
---

# clipboard

Send text to the user's **host** clipboard (their Mac) from inside the container, so they can paste it directly. Use this proactively whenever you'd otherwise ask the user to retype something — most commonly a command you want them to run.

## Usage

The helper lives at `/opt/claude/skills/clipboard/clip` (also reachable as `~/.claude/skills/clipboard/clip`). Pass text as arguments or pipe it on stdin:

```bash
# a command you want the user to run
/opt/claude/skills/clipboard/clip 'gh auth login --with-token < token.txt'

# pipe longer / multi-line content
cat some-output.json | /opt/claude/skills/clipboard/clip
```

Trailing newlines are stripped, so a copied command won't auto-execute the moment the user hits Enter after pasting.

After running it, tell the user it's on their clipboard — e.g. *"Copied to your clipboard — paste it to run."* Don't make them hunt for it.

## When to use it

- You want the user to run a command themselves (interactive logins like `gcloud auth login`, anything you can't or shouldn't run for them).
- A token, URL, file path, or snippet would be tedious or error-prone to retype.
- The user asks to "copy this" / "put it on my clipboard."

Still **show** the text in your reply too — the clipboard is a convenience, not a replacement for telling the user what you copied.

## How it works (and why it's done this oddly)

`clip` writes an [OSC 52](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h2-Operating-System-Commands) escape sequence to the terminal pty. The roundabout path is forced by how this container runs:

- The **Bash tool's stdout is captured by Claude Code** and rendered in its UI — it never reaches the real terminal, so an escape printed to stdout does nothing.
- **`/dev/tty` is unusable** in a tool subprocess — there's no controlling terminal (its `open()` fails even though the node looks writable).
- **PID 1** (the `claude` process) owns the pty that `docker run -t` allocated, and that pty *is* the user's terminal. `clip` writes the OSC 52 sequence to `/proc/1/fd/1` (falling back to `/dev/pts/0`). The terminal emulator consumes OSC 52 without displaying it, so it copies cleanly to the host clipboard without disturbing the screen.

## Limitations

- **The terminal emulator must support OSC 52 clipboard writes.** iTerm2, Ghostty, kitty, WezTerm, and Alacritty do (some need it enabled in settings). macOS Terminal.app does **not**. If a copy silently doesn't land, this is almost always why — tell the user to check their terminal's clipboard/OSC 52 setting.
- **One-way.** It can write the clipboard but not read it. To get text *from* the user, ask them to paste it into the chat.
- **~74 KB cap.** OSC 52 payloads are limited (~99000 base64 chars); `clip` errors out above that rather than truncating silently. For larger content, write a file under the mounted project dir (bind-mounted to the host) instead.
- **Host multiplexers.** If the user runs `claude` inside a host-side tmux/screen, set `CLAUDE_CLIP_MUX=tmux` (or `screen`) so the escape is wrapped for passthrough — and the multiplexer must have clipboard passthrough enabled (`set -g set-clipboard on` for tmux).
