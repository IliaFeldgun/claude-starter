#!/usr/bin/env bash
# Symlinked to python3/python/python3.12 on Mason's PATH (prepended by the nvim
# wrapper). Mason's pypi installer shells out to `python3 -m venv` then
# `venv/bin/python -m pip install …`; this routes both through uv so the
# container needs no system pip/ensurepip. Any other invocation is passed
# through to the real interpreter unchanged.
set -euo pipefail

self=$(basename "$0")

# Resolve the next interpreter of this name on PATH, skipping any entry that is
# this shim (so we never re-exec ourselves into an infinite loop).
src="$0"
case "$src" in */*) ;; *) src=$(command -v "$src" 2>/dev/null || echo "$src") ;; esac
me=$(readlink -f "$src" 2>/dev/null || echo "$src")

real=""
IFS=:
for d in $PATH; do
  cand="$d/$self"
  [ -x "$cand" ] || continue
  [ "$(readlink -f "$cand" 2>/dev/null)" = "$me" ] && continue
  real="$cand"; break
done
unset IFS
[ -n "$real" ] || real="/usr/bin/$self"

if [ "${1:-}" = "-m" ] && [ "${2:-}" = "venv" ]; then
  shift 2
  args=("$@")
  target="${args[${#args[@]}-1]}"
  sys=()
  for a in "${args[@]}"; do
    [ "$a" = "--system-site-packages" ] && sys=(--system-site-packages)
  done
  uv venv "${sys[@]}" "$target" >&2
  purelib=$("$target/bin/python" -c 'import sysconfig; print(sysconfig.get_path("purelib"))')
  mkdir -p "$purelib/pip"
  : >"$purelib/pip/__init__.py"
  cat >"$purelib/pip/__main__.py" <<'PY'
import os, subprocess, sys

argv = [a for a in sys.argv[1:] if a != "--disable-pip-version-check"]
# Mason's self-upgrade step would overwrite this shim with real pip; no-op it.
if argv[:1] == ["install"] and all(a in ("pip", "--upgrade", "-U") for a in argv[1:]):
    sys.exit(0)
os.environ["VIRTUAL_ENV"] = sys.prefix
sys.exit(subprocess.call(["uv", "pip", *argv]))
PY
  exit 0
fi

exec "$real" "$@"
