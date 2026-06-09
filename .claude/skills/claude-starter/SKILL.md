---
name: claude-starter
description: Use when editing this repo (claude-starter) — the Dockerfile, entrypoint, `claude` wrapper, `skills.py`, `skills.in.yaml`/`skills.yaml`, or anything under `local-skills/`. This repo builds the very container Claude is running inside, so changes only take effect after a rebuild. Triggers on edits under `/workspace/{Dockerfile,entrypoint.sh,claude,docker-compose.yaml,Makefile,skills.py,skills.in.yaml,skills.yaml,apt-packages.list,local-skills/**}` or questions about how this container is built, how skills are baked in, or why something installed in the container isn't visible to the user (or vice versa).
---

# claude-starter

You are running inside the very container this repo builds. Editing files here changes the image used for *the next* `claude` invocation, not the current one. Internalize the layout before touching anything.

## What this repo is

A thin wrapper that packages [Claude Code](https://github.com/anthropics/claude-code) into a reproducible Ubuntu container with a curated set of skills, language toolchains (Node, Python/uv, Rust, Helm, kubectl, gh, Neovim/LazyVim), and the Datadog MCP CLI. The user invokes it via the `claude` shim, which runs `docker compose run --rm claude` against `docker-compose.yaml`.

```
/workspace/
├── Dockerfile              # image definition; all tooling installs live here
├── docker-compose.yaml     # mounts + volumes for the runtime container
├── entrypoint.sh           # runs on every container start (symlinks, seeds)
├── claude                  # host-side shell wrapper; what the user types
├── apt-packages.list       # passed to apt-get during image build
├── Makefile                # skills clone/freeze/install/clean
├── skills.py               # skill installer (pulls upstream skill repos)
├── skills.in.yaml          # declared upstream skill repos + refs
├── skills.yaml             # pinned commit SHAs (lockfile for skills.in.yaml)
└── local-skills/           # SKILLs maintained in-tree; baked into the image
    ├── uv/SKILL.md
    ├── bat/SKILL.md
    └── gh-readonly-token/SKILL.md
```

## Containerization: what's shared with the host and what isn't

**This is the single most important thing to keep straight when editing here.** Changes that look right inside the container can be invisible to the user's host shell, and vice versa.

### `/workspace` is bind-mounted from the user's host

From `docker-compose.yaml`:

```yaml
volumes:
  - ${CLAUDE_WORKSPACE:-.}:/workspace
```

The `claude` wrapper sets `CLAUDE_WORKSPACE="$PWD"` before invoking compose, so whatever directory the user ran `claude` from on their Mac is what shows up at `/workspace` inside the container. Right now, since the user ran `claude` from inside this repo, `/workspace` *is* this repo on their Mac.

**Implications when editing:**
- Files you write under `/workspace/...` are instantly visible on the user's host — no copy step, no patch handoff.
- Don't tell the user to "apply this patch on your Mac" — just edit.
- `git` operations under `/workspace` go through the host's working tree. The git identity is configured locally to `ilia@pinecone.io` / `IliaFeldgun`.

### Credentials and home dir are **not** shared

The container has its own home directory on a Docker named volume:

```yaml
volumes:
  - claude-data:/home/ubuntu
```

`claude-data` is a persistent Docker volume — it survives container restarts but lives entirely inside Docker's storage, completely separate from the user's macOS home.

**This means:**
- `~/.claude/`, `~/.config/`, `~/.cache/`, `~/.local/`, `~/.ssh/`, `~/.aws/`, `~/.config/gh/`, `~/.gitconfig`, etc. inside the container are **not** the user's host versions. Logging into `gh` here doesn't log them in on their Mac, and vice versa.
- `claude auth login`, `gh auth login`, `aws configure`, kube contexts, Datadog MCP auth — all of it is container-local.
- The Datadog MCP token in `datadog-mcp-auth-url.txt` and similar bootstrap files are how the user gets credentials *into* the container; they aren't a substitute for host creds.
- If a host tool (e.g. the user's Mac `gcloud`) holds a credential, the container can't see it unless you mount it in or pipe it through. Don't assume parity.
- Conversely: nothing you install or auth into in the container leaks to the host.

### Practical consequences

| Situation | What this means |
| --- | --- |
| User says "I'm logged into gh on my Mac" | The container is not. It needs its own `GH_TOKEN` (see the `gh-readonly-token` skill) or a separate `gh auth login`. |
| User asks why `aws sso login` from the container didn't work on their Mac | It didn't, and it won't. Separate credential stores. |
| You want to test a Dockerfile change | The current container is already built; you need to rebuild and have the user re-enter (see below). |
| You touched `~/.bashrc` inside the container | It's persistent across restarts (lives in `claude-data`) but invisible on the host. |

## How skills get into the image

Two paths, both end up under `/opt/claude/skills` (which `entrypoint.sh` symlinks to `~/.claude/skills` at runtime so the volume mount doesn't shadow them):

1. **Upstream skills** — declared in `skills.in.yaml`, pinned in `skills.yaml`, cloned into `.skills/` by `skills.py clone`, then copied into the image by `skills.py install-skills --target /opt/claude/skills` during the Docker build.
   - To add one: edit `skills.in.yaml`, run `make skills && make freeze` to lock the commit, then rebuild.
   - To bump: `make freeze` (re-pins to latest of declared ref), commit the updated `skills.yaml`, rebuild.

2. **Local skills** — anything under `local-skills/<name>/SKILL.md` is copied wholesale during the image build (see the last `RUN` in `Dockerfile`). Use this for skills maintained in-tree, like `uv`, `bat`, and `gh-readonly-token`.

3. **Project-local skills** (this file's home) — `.claude/skills/<name>/SKILL.md` under `/workspace/...`. These are **not** baked into the image; they're picked up by Claude only when `/workspace` is mounted at this repo. Use this path for skills that only make sense when editing *this specific* project.

## Testing changes

The current `claude` session is using the previously-built image. To exercise changes to `Dockerfile`, `entrypoint.sh`, `apt-packages.list`, `local-skills/`, `skills.*`, etc., the user needs to rebuild:

```bash
# on the host, from anywhere the `claude` wrapper resolves
claude --update            # forces `docker compose build --pull --no-cache claude`
```

Then re-enter (`claude` from their target workspace dir).

You can sanity-check syntax without a full rebuild:
- `docker compose -f /workspace/docker-compose.yaml config` to validate compose YAML.
- `bash -n /workspace/entrypoint.sh` and `bash -n /workspace/claude` for shell syntax.
- `uv run --with pyyaml python /workspace/skills.py clone --help` for `skills.py` smoke.
- `actionlint` is installed if you ever add `.github/workflows/`.

But you cannot test a Dockerfile change end-to-end from inside this container — that requires the host `docker` daemon, which is not exposed here.

## Common edits and where they land

| Goal | File(s) to edit | Then |
| --- | --- | --- |
| Add an apt package | `apt-packages.list` | rebuild |
| Install a binary not in apt | new `RUN` in `Dockerfile` (multi-arch — see kubectl/gh/nvim blocks for the `dpkg --print-architecture` pattern) | rebuild |
| Add an in-tree skill | new dir under `local-skills/<name>/SKILL.md` | rebuild |
| Add an upstream skill | append to `skills.in.yaml`, then `make skills freeze` | rebuild |
| Bump pinned upstream skills | `make freeze`, commit `skills.yaml` | rebuild |
| Change container startup behavior | `entrypoint.sh` (remember: runs every start, must be idempotent — see the existing `~/.claude/skills` symlink and nvim seed for the pattern) | rebuild |
| Change how the host launches claude | `claude` (shell wrapper on host PATH) or `docker-compose.yaml` | next invocation picks it up; no rebuild |
| Add a project-local skill for editing this repo | `.claude/skills/<name>/SKILL.md` | no rebuild — picked up on next claude session against this `/workspace` |

## Conventions to honor

- **Multi-arch installs.** Every binary the Dockerfile downloads branches on `dpkg --print-architecture` (`amd64` vs `arm64`). Follow the same pattern when adding one — the user runs this on Apple Silicon.
- **Skills survive the volume mount.** Anything that needs to be available under `~/.claude/skills` must be installed to `/opt/claude/skills` and symlinked by `entrypoint.sh`. Installing directly into `/home/ubuntu/.claude/skills` during the build will be hidden by the `claude-data` volume mount at runtime.
- **Runtime vs build-time setup.** Anything that depends on the volume-mounted `/home/ubuntu` (creating dirs, seeding configs, making symlinks) goes in `entrypoint.sh`, not in a Dockerfile `RUN`. Build-time writes to `/home/ubuntu` get shadowed by the volume mount.
- **`entrypoint.sh` must be idempotent** — it runs on every `docker compose run`. Guard with `if [ ! -e ... ]`.
- **No narrative comments.** Match the prevailing style: short `#` notes where the *why* isn't obvious, nothing else.
- **Commits are new commits by default**, not amends. Set `user.email=ilia@pinecone.io` / `user.name=IliaFeldgun` *locally* in `/workspace` (no `--global`) if git complains about missing identity.
