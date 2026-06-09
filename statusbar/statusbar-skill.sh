#!/bin/sh
# PreToolUse hook (matcher: Skill). Records the just-invoked skill name to a
# per-session state file that statusline.sh reads. Never blocks the tool.
input=$(cat)
sid=$(printf '%s' "$input" | jq -r '.session_id // "default"')
skill=$(printf '%s' "$input" | jq -r '.tool_input.skill // empty')
[ -z "$skill" ] && exit 0
mkdir -p "$HOME/.claude/state"
printf '%s' "$skill" > "$HOME/.claude/state/skill-$sid"
exit 0
