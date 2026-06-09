#!/bin/sh
# Custom statusline: prepends the most-recently-loaded skill (recorded by
# record-skill.sh) to dir / branch / model. A custom statusLine fully replaces
# the default, so we re-emit the bits worth keeping.
input=$(cat)
sid=$(printf '%s' "$input" | jq -r '.session_id // "default"')
model=$(printf '%s' "$input" | jq -r '.model.display_name // empty')
dir=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // empty')
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty')

skill=""
f="$HOME/.claude/state/skill-$sid"
[ -f "$f" ] && skill=$(cat "$f")

mcp=""
fm="$HOME/.claude/state/mcp-$sid"
[ -f "$fm" ] && mcp=$(cat "$fm")

# Two numbers from the transcript:
#   total  -- context-window occupancy = input side of the latest assistant turn
#             (input + cache_read + cache_creation); shown as the %/window.
#   delta  -- new tokens added since the last real user prompt (input +
#             cache_creation summed over each assistant turn after it; cache_read
#             is old context, excluded). Deduped by message.id because one
#             assistant message spans several transcript lines that repeat usage.
# A "real prompt" is a user entry that is neither an injected system-reminder
# (isMeta) nor a tool_result. tail keeps the parse cheap on long transcripts;
# 400 lines comfortably covers one prompt + its tool calls.
tok_disp=""
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  pair=$(tail -n 400 "$transcript" | jq -R 'fromjson? // empty' 2>/dev/null | jq -rs '
    def isprompt: .type=="user" and (.isMeta != true)
      and ((.message.content|type)=="string"
           or ((.message.content|type)=="array"
               and ((.message.content|map(.type)|index("tool_result"))|not)));
    . as $rows | ($rows|length) as $n
    | (reduce range(0;$n) as $i (-1; if ($rows[$i]|isprompt) then $i else . end)) as $b
    | ([ $rows[] | select(.message.usage) ] | last | .message.usage
         | (.input_tokens//0)+(.cache_read_input_tokens//0)+(.cache_creation_input_tokens//0)) as $total
    | ([ $rows[ ($b+1) : $n ][] | select(.type=="assistant" and .message.usage)
          | {id: .message.id, m: .message.usage} ] | unique_by(.id)
        | map((.m.input_tokens//0)+(.m.cache_creation_input_tokens//0)) | add // 0) as $delta
    | "\($delta) \($total // 0)"' 2>/dev/null)
  delta=${pair% *}
  total=${pair#* }
  if [ -n "$total" ] && [ "$total" != "null" ] && [ "$total" -gt 0 ] 2>/dev/null; then
    # Context window from the model name ("... (1M context)"); default 200k.
    win=200000
    case "$model" in *1M*) win=1000000;; esac
    tok_disp=$(awk -v d="${delta:-0}" -v n="$total" -v w="$win" '
      function fmt(x){ if(x>=1e6)return sprintf("%gM",x/1e6); else if(x>=1e3)return sprintf("%.0fk",x/1e3); else return sprintf("%d",x) }
      BEGIN{ printf "₪+%s₪  📜%d%%/%s📜", fmt(d), (w>0)?int(n*100/w+0.5):0, fmt(w) }')
  fi
fi

branch=""
if [ -n "$dir" ] && git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -C "$dir" branch --show-current 2>/dev/null)
fi

# PR number for the current branch, cached by statusbar-pr.sh as "<branch>\t<n>".
# Only show it when the cache matches the branch we're actually on.
pr=""
fp="$HOME/.claude/state/pr-$sid"
if [ -f "$fp" ] && [ -n "$branch" ] && [ "$(cut -f1 "$fp")" = "$branch" ]; then
  pr=$(cut -f2 "$fp")
fi

# Two rows so a narrow terminal wraps instead of truncating: identity/location
# on row 1, model/usage on row 2. Each row is truncated to width independently.
line1=""
[ -n "$skill" ] && line1="🎯${skill}🎯  "
[ -n "$mcp" ] && line1="$line1📡${mcp}📡 "
[ -n "$dir" ] && line1="$line1$(basename "$dir")"
[ -n "$branch" ] && line1="$line1  ⎇ $branch"
[ -n "$pr" ] && line1="$line1 🔀#$pr"

line2=""
[ -n "$model" ] && line2="$model"
[ -n "$tok_disp" ] && line2="$line2  $tok_disp"

out="$line1"
[ -n "$line2" ] && out="$out
$line2"
printf '%s' "$out"
