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

# Resolve the GitHub token slot chosen by the host launcher into $GH_TOKEN for
# this session (overrides any in-container `gh auth login`). Missing 'ro' is
# silent; missing 'pr'/'issue' warns since the user explicitly asked for it.
if [ -n "${CLAUDE_GH_SLOT:-}" ]; then
  f="$GH_TOKEN_DIR/$CLAUDE_GH_SLOT"
  if [ -f "$f" ]; then
    GH_TOKEN=$(cat "$f"); export GH_TOKEN
  else
    unset GH_TOKEN
    if [ "$CLAUDE_GH_SLOT" != ro ]; then
      echo "claude: no token registered for slot '$CLAUDE_GH_SLOT' (run: claude --gh-token $CLAUDE_GH_SLOT:-)" >&2
    fi
  fi
fi

exec "$@"
