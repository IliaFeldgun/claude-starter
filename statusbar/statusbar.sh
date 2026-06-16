#!/bin/sh
input=$(cat)
sid=$(printf '%s' "$input" | jq -r '.session_id // "default"')
model=$(printf '%s' "$input" | jq -r '.model.display_name // empty')
dir=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // empty')
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty')

esc=$(printf '\033')
G="${esc}[38;5;151m"
R="${esc}[38;5;210m"
O="${esc}[38;5;214m"
Z="${esc}[0m"

skill=""
f="$HOME/.claude/state/skill-$sid"
[ -f "$f" ] && skill=$(cat "$f")

mcp=""
fm="$HOME/.claude/state/mcp-$sid"
[ -f "$fm" ] && mcp=$(cat "$fm")

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
    win=200000
    case "$model" in *1M*) win=1000000;; esac
    tok_disp=$(awk -v d="${delta:-0}" -v n="$total" -v w="$win" '
      function fmt(x){ if(x>=1e6)return sprintf("%gM",x/1e6); else if(x>=1e3)return sprintf("%.0fk",x/1e3); else return sprintf("%d",x) }
      BEGIN{ printf "₪+%s₪  📜%d%%/%s📜", fmt(d), (w>0)?int(n*100/w+0.5):0, fmt(w) }')
  fi
fi

branch=""
repo=""
head_diff=""
main_diff=""
short_hash=""
if [ -n "$dir" ]; then
  if git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    branch=$(git -C "$dir" branch --show-current 2>/dev/null)
    short_hash=$(git -C "$dir" rev-parse --short HEAD 2>/dev/null)
    toplevel=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)
    repo=$(basename "${toplevel:-$dir}")
    sum_numstat() { awk -v g="$G" -v r="$R" -v z="$Z" '
      { a += $1; d += $2 }
      END { if (a || d) printf "%s+%d%s/%s-%d%s", g, a, z, r, d, z }'; }
    head_diff=$(git -C "$dir" diff --numstat HEAD 2>/dev/null | sum_numstat)
    base=$(git -C "$dir" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@')
    [ -z "$base" ] && base=main
    if [ -n "$branch" ] && [ "$branch" != "$base" ] \
       && git -C "$dir" rev-parse --verify "$base" >/dev/null 2>&1; then
      main_diff=$(git -C "$dir" diff --numstat "$base"...HEAD 2>/dev/null | sum_numstat)
    fi
  else
    repo=$(basename "$dir")
  fi
fi

pr=""
fp="$HOME/.claude/state/pr-$sid"
if [ -f "$fp" ] && [ -n "$branch" ] && [ "$(cut -f1 "$fp")" = "$branch" ]; then
  pr=$(cut -f2 "$fp")
fi

# Which GitHub token slot is live this session (written by entrypoint.sh). 'ro'
# is read-only (green); pr/issue grant writes (orange); deploy is the most
# powerful (red). A '✗' means the requested slot has no token registered.
gh=""
fg="$HOME/.claude/state/gh-slot"
if [ -f "$fg" ]; then
  gh_slot=$(cut -f1 "$fg")
  gh_present=$(cut -f2 "$fg")
  if [ -n "$gh_slot" ]; then
    case "$gh_slot" in ro) gh_c="$G";; deploy) gh_c="$R";; *) gh_c="$O";; esac
    [ "$gh_present" = 1 ] || gh_slot="$gh_slot✗"
    gh="${gh_c}🔑${gh_slot}${Z}"
  fi
fi

line0=""
[ -n "$dir" ] && line0="📂 $dir"
[ -n "$head_diff" ] && line0="$line0 Δ$head_diff"

line1=""
[ -n "$skill" ] && line1="🎯${skill}🎯  "
[ -n "$mcp" ] && line1="$line1📡${mcp}📡 "
[ -n "$repo" ] && line1="$line1📦 $repo "
[ -n "$branch" ] && line1="$line1⎇ $branch"
[ -n "$short_hash" ] && line1="$line1 $short_hash"
[ -n "$main_diff" ] && line1="$line1 Δmain$main_diff"
[ -n "$pr" ] && line1="$line1 🔀#$pr"
[ -n "$gh" ] && line1="$line1 $gh"

line2=""
[ -n "$model" ] && line2="$model"
[ -n "$tok_disp" ] && line2="$line2  $tok_disp"

out=""
for l in "$line0" "$line1" "$line2"; do
  [ -z "$l" ] && continue
  if [ -z "$out" ]; then out="$l"; else out="$out
$l"; fi
done
printf '%s' "$out"
