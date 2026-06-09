#!/bin/sh
# PreToolUse hook (matcher: mcp__.*). Records the MCP server of the just-called
# tool (mcp__<server>__<tool>) to a per-session state file. Never blocks.
input=$(cat)
sid=$(printf '%s' "$input" | jq -r '.session_id // "default"')
tool=$(printf '%s' "$input" | jq -r '.tool_name // empty')
case "$tool" in
  mcp__*) ;;
  *) exit 0 ;;
esac
server=$(printf '%s' "$tool" | sed -E 's/^mcp__//; s/__.*//')
[ -z "$server" ] && exit 0
mkdir -p "$HOME/.claude/state"
printf '%s' "$server" > "$HOME/.claude/state/mcp-$sid"
exit 0
