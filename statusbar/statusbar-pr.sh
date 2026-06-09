#!/bin/sh
# UserPromptSubmit + PostToolUse hook: caches the current branch's PR number to
# a per-session state file the statusline reads. The gh lookup runs detached so
# it never blocks the turn -- the statusline shows the cached value and picks up
# the refresh on a later render. Debounced on branch-unchanged fires (TTL); a
# git push / gh pr command forces an immediate refresh.
input=$(cat)
sid=$(printf '%s' "$input" | jq -r '.session_id // "default"')
dir=$(printf '%s' "$input" | jq -r '.cwd // empty')
command -v gh >/dev/null 2>&1 || exit 0
[ -n "$dir" ] || exit 0

branch=$(git -C "$dir" branch --show-current 2>/dev/null)
state="$HOME/.claude/state/pr-$sid"
mkdir -p "$HOME/.claude/state"

# No branch, or a trunk branch: nothing to show.
case "$branch" in ""|main|master) rm -f "$state"; exit 0 ;; esac

# A push or PR command forces a refresh; otherwise debounce on (same branch,
# cache younger than TTL) so firing on every tool stays a cheap no-op.
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
case "$cmd" in
  *"git push"*|*"gh pr create"*|*"gh pr "*) ;;
  *)
    if [ -f "$state" ]; then
      age=$(( $(date +%s) - $(stat -c %Y "$state" 2>/dev/null || echo 0) ))
      [ "$(cut -f1 "$state")" = "$branch" ] && [ "$age" -lt 30 ] && exit 0
    fi ;;
esac

# Detached, timeout-bounded; tmp+mv so the statusline never reads a half-write.
( cd "$dir" 2>/dev/null || exit 0
  pr=$(timeout 8 gh pr view --json number -q .number 2>/dev/null)
  printf '%s\t%s' "$branch" "$pr" > "$state.tmp" 2>/dev/null && mv "$state.tmp" "$state" ) &
exit 0
