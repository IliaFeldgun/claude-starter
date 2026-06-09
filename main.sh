#!/usr/bin/env bash
set -euo pipefail
COMPOSE_PROJECT_NAME=claude
export CLAUDE_WORKSPACE="$PWD"

die() { echo "claude: $*" >&2; exit 1; }

# Where this repo (with docker-compose.yaml) lives. install.sh bakes the path
# into the generated stub via --compose-dir; fall back to resolving our own
# location so running main.sh directly still works.
COMPOSE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)

update=0
slot=ro
register_spec=""
rotate=0
cmd=()
args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --compose-dir) shift; [[ $# -gt 0 ]] || die "--compose-dir needs a path"; COMPOSE_DIR="$1" ;;
    --compose-dir=*) COMPOSE_DIR="${1#*=}" ;;
    --update) update=1 ;;
    --gh-token) shift; [[ $# -gt 0 ]] || die "--gh-token needs SLOT[:TOKEN]"; register_spec="$1" ;;
    --gh-token=*) register_spec="${1#*=}" ;;
    --gh-token-rotate) rotate=1 ;;
    --pr) slot=pr ;;
    --issue) slot=issue ;;
    --deploy) slot=deploy ;;
    --ro) slot=ro ;;
    --nvim|--nvim-dev) cmd=(-w /workspace claude nvim) ;;
    --nvim-home) cmd=(-w /home/ubuntu claude nvim) ;;
    --bash) cmd=(-w /home/ubuntu claude bash) ;;
    *) args+=("$1") ;;
  esac
  shift
done

[[ -f "$COMPOSE_DIR/docker-compose.yaml" ]] || die "no docker-compose.yaml in $COMPOSE_DIR"
compose=(docker compose -p $COMPOSE_PROJECT_NAME -f "$COMPOSE_DIR/docker-compose.yaml")

# Mount the host's Neovim config (settings/keymaps) read-only into the container
# when it exists; plugin data/state/cache stay container-local. Override the
# source with CLAUDE_NVIM_CONFIG, or set it empty to disable.
nvim_config="${CLAUDE_NVIM_CONFIG-$HOME/.config/nvim}"
if [[ -n "$nvim_config" && -d "$nvim_config" ]]; then
  export CLAUDE_NVIM_CONFIG="$nvim_config"
  compose+=(-f "$COMPOSE_DIR/nvim/docker-compose.nvim.yaml")
fi

if [[ $update -eq 1 ]]; then
  "${compose[@]}" build --pull --no-cache claude
fi

# Store a GitHub token in the persistent claude-data volume (one file per slot,
# written by entrypoint.sh). The value travels on stdin only — never in argv/env,
# never to the host disk or settings.json.
register_slot() {
  printf '%s' "$2" | "${compose[@]}" run --rm -T -e CLAUDE_GH_REGISTER="$1" claude true
}

# claude --gh-token SLOT[:TOKEN] — register a single slot. Omit TOKEN (or use
# "-") to enter it hidden / read it from a pipe.
if [[ -n "$register_spec" ]]; then
  rslot=${register_spec%%:*}
  case "$rslot" in
    pr|issue|deploy|ro) ;;
    *) die "unknown token slot '$rslot' (use pr, issue, deploy, or ro)" ;;
  esac
  if [[ "$register_spec" == *:* ]]; then token=${register_spec#*:}; else token="-"; fi
  if [[ -z "$token" || "$token" == "-" ]]; then
    if [[ -t 0 ]]; then
      printf 'Paste %s token (input hidden): ' "$rslot" >&2
      read -rs token; echo >&2
    else
      read -r token || true    # piped; capture partial input even without trailing newline
    fi
  fi
  [[ -n "$token" ]] || die "empty token for slot '$rslot'"
  register_slot "$rslot" "$token"
  exit $?
fi

# claude --gh-token-rotate — walk every slot in sequence, prompting for a freshly
# regenerated token. Blank input skips that slot, leaving its current token in place.
if [[ $rotate -eq 1 ]]; then
  [[ -t 0 ]] || die "--gh-token-rotate needs an interactive terminal"
  echo "Rotating GitHub tokens. Regenerate each at" >&2
  echo "  https://github.com/settings/personal-access-tokens" >&2
  echo "then paste below. Leave blank to skip a slot." >&2
  echo >&2
  for rslot in ro deploy issue pr; do
    printf 'Paste %s token (blank to skip, input hidden): ' "$rslot" >&2
    read -rs token; echo >&2
    if [[ -z "$token" ]]; then
      echo "claude: skipped '$rslot'" >&2
      continue
    fi
    register_slot "$rslot" "$token"
  done
  exit 0
fi

# Hand the chosen slot to entrypoint.sh, which resolves it to $GH_TOKEN inside
# the container. 'ro' is the default; missing 'pr'/'issue' tokens warn there.
exec "${compose[@]}" run --build --rm -e CLAUDE_GH_SLOT="$slot" "${cmd[@]:-claude}" ${args[@]:-}
