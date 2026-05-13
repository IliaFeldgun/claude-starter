---
name: uv
description: Use uv for all Python work in this container — running scripts, installing packages, creating venvs, and managing project dependencies. Triggers on any Python task (`python`, `pip`, `pip3`, `venv`, `virtualenv`, `poetry`, `pipx`, `.py` files, requirements.txt, pyproject.toml). Prefer uv commands over the raw equivalents.
---

# uv

This container has [uv](https://docs.astral.sh/uv/) installed system-wide and a shared virtualenv at `/opt/venv` already on `PATH`. Use `uv` for everything Python — it's faster, deterministic, and avoids polluting system Python.

## Rules

- **Never** call `pip` / `pip3` directly. Use `uv pip install ...` (writes into the active venv) or `uv add ...` (writes into `pyproject.toml`).
- **Never** create venvs with `python -m venv` or `virtualenv`. Use `uv venv [path]`.
- **Never** invoke `poetry`, `pipx`, or `pip-tools`. uv covers all of those.
- Prefer `uv run` over bare `python` when the script needs deps that aren't already in the active venv.

## Recipes

| Task | Command |
| --- | --- |
| Run a script with one-off deps | `uv run --with requests --with rich script.py` |
| Run a project script (uses pyproject.toml) | `uv run python -m mypkg` or `uv run mycli` |
| Add a dep to a project | `uv add httpx` |
| Add a dev dep | `uv add --dev pytest` |
| Install into the shared `/opt/venv` | `uv pip install httpx` |
| Sync a project's lockfile into its venv | `uv sync` |
| Create a fresh venv | `uv venv .venv` |
| One-off Python with a lib not installed | `uv run --with pyyaml python -c 'import yaml; ...'` |
| Run a tool without installing it persistently | `uvx ruff check .` |
| Pin Python version for a project | `uv python pin 3.12` |

## Inside this image specifically

- `/opt/venv` is on `PATH`, so `python` and installed entry points work without activation.
- To add packages to that shared venv: `uv pip install <pkg>` (no `--system` needed; uv picks up `VIRTUAL_ENV`/the active venv).
- For per-project work, `cd` into the project and use `uv run` / `uv sync` — uv will create/use a project-local `.venv`.

## When NOT to switch tools

If a repo's docs, Makefile, or CI explicitly call `pip` / `poetry` / `python -m venv`, leave those as-is. Only swap to uv for ad-hoc commands you're running yourself, or when the user asks for a migration.
