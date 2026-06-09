---
name: bat
description: Use `bat` instead of `cat` for viewing files in the terminal. Triggers on any task where the user runs or asks for `cat <file>`, `cat -n`, "show me this file in the shell", "print this file", or pipes that end in `cat` for display. Prefer `bat` for its syntax highlighting, line numbers, and paging behavior. Does NOT apply to the Read tool — Read remains the preferred way for Claude to view file contents.
---

# bat

This container has [`bat`](https://github.com/sharkdp/bat) preinstalled. Ubuntu ships the binary as `batcat`; a symlink at `/usr/local/bin/bat` makes it available as `bat`.

## Rules

- When you would otherwise run `cat <file>` in a shell, run `bat <file>` instead.
- This is **shell-only guidance**. For *reading* file contents into your own context, keep using the `Read` tool — don't shell out to `bat` or `cat` for that.
- Inside heredocs, pipelines that *consume* (not display) text, or scripts that depend on raw byte-for-byte `cat` output, keep `cat`. `bat` is for human-facing display.

## Common swaps

| Instead of | Use |
| --- | --- |
| `cat file.py` | `bat file.py` |
| `cat -n file.py` | `bat file.py` (line numbers are default) |
| `cat file1 file2` | `bat file1 file2` |
| `some-cmd \| cat` (for display) | `some-cmd \| bat` (or just `some-cmd`) |
| `cat file \| grep foo` | `grep foo file` (don't reach for `bat` here either — no UUOC) |

## Useful flags

- `bat -p file` — plain mode, no decorations (closer to `cat`, still highlighted). Use when piping into another tool that expects clean output but you still want highlighting on a TTY.
- `bat -pp file` — fully plain, no highlighting, no decorations. Drop-in `cat` replacement when something downstream is fussy.
- `bat --paging=never file` — disable the pager (useful in non-interactive contexts; `bat` auto-disables paging when stdout isn't a TTY anyway).
- `bat -A file` — show non-printable characters (like `cat -A`).
- `bat -r 10:20 file` — print only lines 10–20.

## No decorative banners between files

When looping over multiple files, **do not** wrap each one in a hand-rolled header like:

```bash
for f in *.txt; do echo "═══ $f ═══"; cat "$f"; done    # NO
for f in *.txt; do echo "=== $f ==="; cat "$f"; done    # NO
for f in *.txt; do printf '\n--- %s ---\n' "$f"; cat "$f"; done   # NO
```

Just do one of these instead:

```bash
bat *.txt              # bat's own header shows the filename
for f in *.txt; do bat "$f"; done
for f in *.txt; do cat "$f"; done   # if you really need raw cat, no banner
```

`bat` already prints a filename header per file. Adding your own on top is visual noise.

## When NOT to switch

- Inside shell scripts, Makefiles, Dockerfiles, or anything checked into the repo — keep `cat`. Don't introduce a `bat` dependency into committed code.
- Inside heredocs (`cat <<EOF ... EOF`) — that's a shell construct, not a display call.
- When the user explicitly asks for `cat`.
