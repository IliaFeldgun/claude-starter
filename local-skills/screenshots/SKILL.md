---
name: screenshots
description: When the user refers to a screenshot, screen grab, or "the image I just took/saved" without giving a path, look in /SCREENSHOTS — the host's screenshots folder is usually bind-mounted there. Triggers on "look at my screenshot", "see the screenshot", "the screen grab I took", "check the image I saved", "my latest screenshot", or any reference to a screenshot whose location isn't spelled out. The mount is optional, so check it exists first.
---

# screenshots

The `claude` wrapper can bind-mount a host folder (e.g. the user's macOS screenshots
dir) at `/SCREENSHOTS` inside the container. When present, that's where the user's
screenshots live — so a request like "look at my last screenshot" almost always means
a file under `/SCREENSHOTS`, even when no path is given.

## The mount is optional — check before assuming

It only exists if the user installed with `--screenshots PATH` (baked into the stub by
`install.sh`) or passed `--screenshots PATH` for the run. If they didn't, `/SCREENSHOTS`
won't be there. Easy to check:

```bash
[ -d /SCREENSHOTS ] && echo present || echo absent
```

- **Present** → look there for the file the user means.
- **Absent** → the user didn't opt in. Don't guess; ask where the image is, or tell
  them they can mount it with `claude --screenshots <host-dir>` (or bake it in via
  `install.sh --screenshots <host-dir>`).

## Finding the right file

The user usually means the **most recent** screenshot. List by modification time:

```bash
ls -t /SCREENSHOTS | head           # newest first
```

Then read it with the `Read` tool (it renders images visually):

- Read `/SCREENSHOTS/<newest>` to see what they're pointing at.

If several are recent and it's ambiguous which one, list the top few with timestamps
(`ls -lt /SCREENSHOTS | head`) and confirm rather than guessing.

## Notes

- It's a live bind mount: files the user adds on the host appear immediately; files you
  write to `/SCREENSHOTS` land back on their host folder.
- Don't hard-code a host path — inside the container the directory is always
  `/SCREENSHOTS` regardless of where it lives on the host.
