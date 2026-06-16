#!/bin/sh
set -e

GH_TOKEN_DIR="$HOME/.config/claude-starter/gh-tokens"

# Registration mode (host: `claude --gh-token SLOT:-`): store the token piped on
# stdin into the persistent volume, then exit without launching. Token never
# appears in argv/env — only on stdin.
if [ -n "${CLAUDE_GH_REGISTER:-}" ]; then
  case "$CLAUDE_GH_REGISTER" in
    pr|issue|deploy|ro) ;;
    *) echo "claude: unknown token slot '$CLAUDE_GH_REGISTER'" >&2; exit 2 ;;
  esac
  mkdir -p "$GH_TOKEN_DIR"; chmod 700 "$GH_TOKEN_DIR"
  ( umask 077; cat > "$GH_TOKEN_DIR/$CLAUDE_GH_REGISTER" )
  echo "claude: stored '$CLAUDE_GH_REGISTER' token in container volume" >&2
  exit 0
fi

# ~/.claude is a runtime mount, so we point it at the baked-in skills here.
# Skip if the user already has something at ~/.claude/skills.
mkdir -p "$HOME/.claude"
if [ ! -e "$HOME/.claude/skills" ] && [ ! -L "$HOME/.claude/skills" ]; then
  ln -s /opt/claude/skills "$HOME/.claude/skills"
fi

# Wire the statusbar renderer + hooks into settings.json, preserving anything
# else. Declarative: prune every hook/statusLine we own (command under
# /opt/claude/bin/statusbar*), then re-add the current set. So this is idempotent
# and self-healing — renaming or dropping one of our scripts can't leave a dead
# hook behind, and foreign hooks are never touched. jq failure must not block startup.
SETTINGS="$HOME/.claude/settings.json"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
TMP="$SETTINGS.tmp"
jq '
  def mine: (. // "") | startswith("/opt/claude/bin/");
  def prune: map(.hooks |= map(select(.command | mine | not))) | map(select(.hooks | length > 0));
  .hooks.PreToolUse      |= (. // [] | prune)
  | .hooks.PostToolUse   |= (. // [] | prune)
  | .hooks.Stop          |= (. // [] | prune)
  | .hooks.UserPromptSubmit |= (. // [] | prune)
  | .hooks.PreToolUse += [
      {matcher: "Skill",    hooks: [{type: "command", command: "/opt/claude/bin/statusbar-skill.sh"}]},
      {matcher: "mcp__.*", hooks: [{type: "command", command: "/opt/claude/bin/statusbar-mcp.sh"}]}
    ]
  | .hooks.PostToolUse += [{hooks: [{type: "command", command: "/opt/claude/bin/statusbar-pr.sh"}]}]
  | .hooks.UserPromptSubmit += [
      {hooks: [{type: "command", command: "/opt/claude/bin/statusbar-clear.sh"}]},
      {hooks: [{type: "command", command: "/opt/claude/bin/statusbar-pr.sh"}]}
    ]
  | (if (.statusLine.command | mine) or (.statusLine == null)
     then .statusLine = {type: "command", command: "/opt/claude/bin/statusbar.sh"}
     else . end)
' "$SETTINGS" > "$TMP" 2>/dev/null && mv "$TMP" "$SETTINGS" || rm -f "$TMP"

# Seed LazyVim config on first run; user-writable so customisations stick.
if [ ! -e "$HOME/.config/nvim" ] && [ -d /opt/nvim-starter ]; then
  mkdir -p "$HOME/.config"
  cp -r /opt/nvim-starter "$HOME/.config/nvim"
fi

# Register the Datadog MCP proxy (preprod org). The binary is baked into the
# image; this wires it into Claude Code as a stdio server on the user scope.
# Idempotent: skip if already registered. OAuth login is interactive and done
# once by the user (`datadog_mcp_cli login --custom-domain preprod.datadoghq.com`);
# the token persists under ~/.config/Datadog.
if command -v datadog_mcp_cli >/dev/null 2>&1 \
   && ! claude mcp get datadog-mcp >/dev/null 2>&1; then
  claude mcp add -s user datadog-mcp -- \
    datadog_mcp_cli --custom-domain preprod.datadoghq.com >/dev/null 2>&1 || true
fi

# Register + install the baked-in local plugin marketplaces (copied to
# /opt/claude/plugins at build time). Each subtree with .claude-plugin/marketplace.json
# is a directory-source marketplace. jq-guarded so steady state spawns no `claude`:
# re-`add` only when the recorded source path drifts (self-heals stale state, e.g.
# a marketplace that previously pointed at a host checkout), install only what's
# missing. </dev/null keeps any prompt from blocking startup. jq failures are non-fatal.
PLUGINS_SRC=/opt/claude/plugins
MP_DB="$HOME/.claude/plugins/known_marketplaces.json"
INST_DB="$HOME/.claude/plugins/installed_plugins.json"
if command -v claude >/dev/null 2>&1 && [ -d "$PLUGINS_SRC" ]; then
  find "$PLUGINS_SRC" -path '*/.claude-plugin/marketplace.json' 2>/dev/null | while read -r mf; do
    mp_root=$(dirname "$(dirname "$mf")")
    mp_name=$(jq -r '.name // empty' "$mf" 2>/dev/null)
    [ -n "$mp_name" ] || continue
    have=$(jq -r --arg n "$mp_name" '.[$n].source.path // empty' "$MP_DB" 2>/dev/null)
    if [ "$have" != "$mp_root" ]; then
      claude plugin marketplace add "$mp_root" </dev/null >/dev/null 2>&1 || true
    fi
    for p in $(jq -r '.plugins[].name // empty' "$mf" 2>/dev/null); do
      key="${p}@${mp_name}"
      ins=$(jq -r --arg k "$key" '.plugins | has($k)' "$INST_DB" 2>/dev/null)
      [ "$ins" = true ] || claude plugin install -s user "$key" </dev/null >/dev/null 2>&1 || true
    done
  done
fi

# Resolve the GitHub token slot chosen by the host launcher into $GH_TOKEN for
# this session (overrides any in-container `gh auth login`). Missing 'ro' is
# silent; missing 'pr'/'issue' warns since the user explicitly asked for it.
# Record "slot<TAB>present" so the statusbar can show which token is actually
# live (the resolved slot, not the launch flag) — slots aren't otherwise
# observable from inside the session.
if [ -n "${CLAUDE_GH_SLOT:-}" ]; then
  f="$GH_TOKEN_DIR/$CLAUDE_GH_SLOT"
  mkdir -p "$HOME/.claude/state"
  if [ -f "$f" ]; then
    GH_TOKEN=$(cat "$f"); export GH_TOKEN
    printf '%s\t1' "$CLAUDE_GH_SLOT" > "$HOME/.claude/state/gh-slot"
  else
    unset GH_TOKEN
    printf '%s\t0' "$CLAUDE_GH_SLOT" > "$HOME/.claude/state/gh-slot"
    if [ "$CLAUDE_GH_SLOT" != ro ]; then
      echo "claude: no token registered for slot '$CLAUDE_GH_SLOT' (run: claude --gh-token $CLAUDE_GH_SLOT:-)" >&2
    fi
  fi
fi

exec "$@"
