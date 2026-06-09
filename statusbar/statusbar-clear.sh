#!/bin/sh
# UserPromptSubmit hook: clears the session's per-turn skill / MCP tags at each
# new user turn. Token usage is left in place -- it tracks context-window
# occupancy (refreshed by statusbar-tokens.sh from the latest assistant turn),
# not per-turn spend, so it should not reset between prompts.
input=$(cat)
sid=$(printf '%s' "$input" | jq -r '.session_id // "default"')
mkdir -p "$HOME/.claude/state"
rm -f "$HOME/.claude/state/skill-$sid" "$HOME/.claude/state/mcp-$sid"
exit 0
