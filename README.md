# claude-starter

A reproducible Ubuntu container that packages [Claude Code](https://github.com/anthropics/claude-code) with a curated set of skills, language toolchains (Node, Python/uv, Rust, Helm, kubectl, gh, Neovim/LazyVim), a custom statusbar, and the Datadog MCP CLI.

You launch it with a `claude` shim on your `PATH`. The shim runs `docker compose run --rm claude` against this repo, mounting whatever directory you're in at a `/WORKSPACE`-prefixed, same-named path inside the container (e.g. `~/code/myproj` → `/WORKSPACE/myproj`), which becomes the container's working dir.

## Install

```bash
git clone --recurse-submodules git@github.com:IliaFeldgun/claude-starter.git
cd claude-starter
./install.sh                 # drops a `claude` stub into ~/.local/bin
```

Use `--recurse-submodules` so the baked-in plugins (see below) come down with the clone. Already cloned without it? Run `git submodule update --init --recursive`.

Clone it anywhere — `install.sh` resolves the repo location and bakes it into the generated `~/.local/bin/claude` stub, which execs `main.sh` with `--compose-dir <repo>`. Make sure `~/.local/bin` is on your `PATH`. The first `claude` invocation builds the image.

## Usage

Run `claude` from any directory you want to work in — that directory becomes the container's working dir (see above):

```bash
cd ~/some/project
claude                       # start Claude Code against this dir
```

Any extra args pass through to `claude` inside the container.

### Flags

| Flag | What it does |
| --- | --- |
| `--update` | Rebuild the image (`docker compose build --pull --no-cache`). Run after editing the Dockerfile, skills, etc. |
| `--bash` | Drop into a shell in the container (home dir) instead of launching Claude. |
| `--nvim` / `--nvim-dev` | Open Neovim (LazyVim) on the mounted project dir. |
| `--nvim-home` | Open Neovim on the container home dir. |
| `--gh-token SLOT[:TOKEN]` | Register a GitHub token into a slot (see below). |
| `--gh-token-rotate` | Walk every slot, prompting for a fresh token each. |
| `--ro` / `--pr` / `--issue` / `--deploy` | Pick which GitHub token slot this session uses (`ro` is the default). |

### GitHub tokens

The container has its own credential store (a persistent Docker volume) — it does **not** see your host's `gh` login. Register fine-grained tokens into named slots; the value travels on stdin only, never in argv/env or to disk on the host:

```bash
claude --gh-token ro:-       # paste a read-only token (input hidden)
claude --gh-token pr:-       # token allowed to open PRs
claude --pr                  # start a session using the `pr` slot
```

Slots: `ro` (default, read-only), `pr`, `issue`, `deploy`. Tokens persist in the container volume across restarts. Rotate them all with `claude --gh-token-rotate`. See the `gh-readonly-token` skill for how to mint a least-privilege token.

### Neovim config

If you have a host Neovim config at `~/.config/nvim`, it's mounted read-only into the container automatically. Override the source with `CLAUDE_NVIM_CONFIG=/path`, or set it empty to disable and use the baked-in LazyVim seed.

## What's shared with your host

- **The mounted project dir** (`/WORKSPACE/<name>`, see above) is bind-mounted from the directory you ran `claude` in — edits are instantly visible on both sides, and git operations go through your host working tree.
- **The container home dir** (`/home/ubuntu`, including `~/.claude`, `~/.config`, `~/.ssh`, `~/.aws`, gh login, kube contexts, MCP auth) lives on a separate Docker volume. It persists across restarts but is **not** your host home — credentials don't cross over in either direction.

## Skills

Three ways skills get in:

- **Upstream** — declared in `skills.in.yaml`, pinned in `skills.yaml`, baked into the image at build time (`make skills && make freeze`, then `claude --update`).
- **Local** — anything under `local-skills/<name>/SKILL.md` is baked in (e.g. `uv`, `bat`, `clipboard`, `gh-readonly-token`).
- **Project-local** — `.claude/skills/<name>/SKILL.md`, picked up only when this repo is the mounted project dir.

## Plugins

Plugin marketplaces under `local-plugins/<group>/<repo>` (each a git submodule with a `.claude-plugin/marketplace.json`) are baked into the image at `/opt/claude/plugins`. On every start, `entrypoint.sh` registers each as a directory-source marketplace and installs its plugins at user scope — idempotently, so they load in every session without your host checkout being mounted. Add one by `git submodule add`-ing the plugin repo under `local-plugins/`, then `claude --update`.

## Repo layout

```
Dockerfile              # image: all tooling installs
docker-compose.yaml     # mounts + volumes
nvim/                   # compose overlay + nvim shims for the host config mount
entrypoint.sh           # runs every start: skill symlink, statusbar wiring, MCP, plugins, gh slot
main.sh                 # the launcher the `claude` shim execs
install.sh              # writes the ~/.local/bin/claude stub
statusbar/              # statusline + hook scripts (skill/mcp/pr indicators)
local-skills/           # in-tree skills baked into the image
local-plugins/          # plugin marketplaces (git submodules) baked into the image
skills.py / skills.*    # upstream skill installer + lockfile
apt-packages.list       # extra apt packages for the build
```

For details on editing the image (and why a change isn't visible until rebuild), see `.claude/skills/claude-starter/SKILL.md`.
