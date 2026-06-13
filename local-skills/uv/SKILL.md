---
name: uv
description: Use uv for all Python work in this container — running scripts, installing packages, creating venvs, and managing project dependencies. Triggers on any Python task (`python`, `pip`, `pip3`, `venv`, `.venv`, `virtualenv`, `activate`, `poetry`, `pipx`, `conda`, `pyenv`, `pdm`, `hatch`, `tox`, `nox`, `pip-tools`, `.py` files, setup.py, requirements.txt, pyproject.toml). Prefer uv commands over the raw equivalents.
---

# uv

This container has [uv](https://docs.astral.sh/uv/) installed system-wide and a shared virtualenv at `/opt/venv` already on `PATH`. Use `uv` for everything Python — it's faster, deterministic, hits a shared cache, and avoids polluting persistent storage.

## Rules

- **Never** call `pip` / `pip3` directly — not on `PATH`, not as `<venv>/bin/pip`, not as `python -m pip`. Bare pip bypasses uv's cache at `~/.cache/uv`, so a second install of the same wheel re-downloads it. Use `uv pip install ...` (writes into the active venv, cache-aware) or `uv add ...` (writes into `pyproject.toml`).
- **Never** create venvs with `python -m venv` or `virtualenv`. Use `uv venv <path>`.
- **Never** invoke `poetry`, `pipx`, or `pip-tools`. uv covers all of those.
- **Never put a venv under the mounted project dir or `/home/ubuntu`.** The project dir (mounted at a path named after the launch directory, e.g. `/myproj`) is the user's Mac bind-mount; `/home/ubuntu` is a persistent VM volume. Both survive container rebuilds. Venvs are large, Python-version-specific, and often hold host-incompatible symlinks (a `.venv` created on the Mac will have dead Homebrew Python symlinks inside this Linux container). Put per-project venvs under `/opt/uv-envs/<name>` — that path is baked into the image as ubuntu-writable, lives on the ephemeral overlay, and gets wiped on container restart.
- **Never `cd` to invoke a uv/python command.** The user wants their shell to stay where they left it. Pass the path as an argument instead — relative to your current cwd (often more readable, and still runnable on the user's Mac since the project dir is a bind-mount) or absolute, whichever fits. Use the tool's own `--project` / `--directory` / `--cwd` flag when it has one, rather than moving the shell.
- **Any inline script (`python -c` / `python3 -c`) or `.py` file that imports a non-stdlib package must run through `uv run --with <pkg> python ...`** — not bare `python`/`python3`. `/opt/venv` only has what's been installed into it, so a bare `python3 -c 'import yaml'` fails with `ModuleNotFoundError` the moment it touches a third-party lib. `uv run --with` provisions the dep (cache-aware) for that one invocation. If the import is pure stdlib (`json`, `os`, `re`, …), bare `python` is fine. When unsure whether a module is stdlib, just use `uv run --with`.

## Where venvs go

| Need | Where | How |
| --- | --- | --- |
| Ad-hoc deps for a one-off command | `/opt/venv` (shared, on PATH) | `uv pip install <pkg>` |
| One-shot tool with project deps (lint, typecheck, format) | nowhere — use uv's cache | `uvx --with-requirements <reqs> <tool> <args>` |
| Isolated env for a project in the mounted dir | `/opt/uv-envs/<project>` | `uv venv --python 3.12 /opt/uv-envs/<project>` |
| Tool you don't want installed | nowhere — uv manages it | `uvx <tool>` |
| `uv sync` / `uv run` against a project in the mounted dir | `/opt/uv-envs/<project>` | `UV_PROJECT_ENVIRONMENT=/opt/uv-envs/<project> uv sync` |

`UV_PROJECT_ENVIRONMENT` relocates the venv that `uv sync` / `uv run` use without touching the project's `pyproject.toml`. Pick a stable per-project name so reruns hit the same env instead of rebuilding.

## Anti-patterns (these all bypass the uv cache or pollute persistent storage)

| Wrong | Right |
| --- | --- |
| `cd /myproj && uv venv .venv` | `uv venv /opt/uv-envs/proj` |
| `cd /myproj && uvx <tool> <path>` | `uvx <tool> myproj/<path>` from your existing cwd, or an absolute path — just don't move the shell |
| `cd /myproj && uv sync` | `UV_PROJECT_ENVIRONMENT=/opt/uv-envs/proj uv sync --project /myproj` (or a relative `--project` from where you are) |
| `<venv>/bin/pip install -r requirements.txt` | `uv pip install --python <venv>/bin/python -r requirements.txt` |
| `<venv>/bin/python -m pip install ...` | same as above |
| `source .venv/bin/activate && pip install ...` | `source .venv/bin/activate && uv pip install ...` |
| `PYTHONPATH=<venv>/lib/python3.x/site-packages uvx <tool> ...` (hack to make a uvx tool see project deps) | `uvx --with-requirements <reqs> <tool> ...` (deps installed in the same ephemeral env as the tool, cached) |
| `uvx --python ./.venv/bin/python <tool>` from the wrong cwd | always pass an absolute path to `--python` |
| `python3 -c 'import yaml; ...'` (third-party import, bare interpreter) | `uv run --with pyyaml python -c 'import yaml; ...'` |
| `python script.py` where `script.py` imports `requests`/`rich`/etc. | `uv run --with requests --with rich python script.py` |

## Recipes

| Task | Command |
| --- | --- |
| Run a script with one-off deps | `uv run --with requests --with rich script.py` |
| Lint/typecheck a mounted project with reqs in `requirements.txt` | `uvx --with-requirements /myproj/requirements.txt pyright /myproj/pkg/` |
| Lint/typecheck a project with `pyproject.toml` | `UV_PROJECT_ENVIRONMENT=/opt/uv-envs/<name> uv run --project /myproj pyright pkg/` |
| Install into the shared `/opt/venv` | `uv pip install httpx` |
| Sync a project's lockfile into a relocated venv | `UV_PROJECT_ENVIRONMENT=/opt/uv-envs/<name> uv sync --project /myproj` |
| Install requirements.txt into a fresh isolated env | `uv venv --python 3.12 /opt/uv-envs/<name> && uv pip install --python /opt/uv-envs/<name>/bin/python -r /myproj/requirements.txt` |
| One-off Python with a lib not installed | `uv run --with pyyaml python -c 'import yaml; ...'` |
| Run a tool without installing it persistently | `uvx ruff check .` |
| Pin Python version for a project | `uv python pin 3.12` |

## Inside this image specifically

- `/opt/venv` is on `PATH`, so `python` and installed entry points work without activation. Default to this for ad-hoc work.
- `/opt/uv-envs/` is ubuntu-writable and ephemeral — your scratch space for per-project venvs.
- **Don't** `cd` into the mounted project and run `uv sync` / `uv venv .venv` — that drops a `.venv/` into the Mac bind-mount. Use `UV_PROJECT_ENVIRONMENT=/opt/uv-envs/<name>` with `--project` (or `--directory`) instead.
- If you see a pre-existing `.venv/` in the mounted project, it was likely created on the host (Mac); its Python interpreter symlinks point at `/opt/homebrew/...` and are dead inside this container. Don't try to reuse it — its `bin/python` won't execute.
- **To just run or import a project's code (verify an API shape, poke at a package, run a one-off snippet), default to the shared global venv** `/opt/venv` — it's already on `PATH`. Install the dep with `uv pip install <pkg>` (or `uv pip install -r <reqs>`) and run the bare `python`. Don't reach for the project's dead `.venv`, and don't stand up a fresh `/opt/uv-envs/<name>` env unless you specifically need isolation (conflicting versions, a real `uv sync` against the lockfile, etc.).
- uv's cache lives at `~/.cache/uv` (persistent across container restarts) — that's intentional and speeds up reinstalls. Every `uv pip install` / `uv run --with` / `uvx` consults it. Only venvs themselves must be ephemeral.

## When NOT to switch tools

If a repo's docs, Makefile, or CI explicitly call `pip` / `poetry` / `python -m venv`, leave those as-is. Only swap to uv for ad-hoc commands you're running yourself, or when the user asks for a migration. The venv-location rule still applies — if a Makefile would land a venv in the mounted project dir, set `UV_PROJECT_ENVIRONMENT` (or equivalent) before invoking it.
