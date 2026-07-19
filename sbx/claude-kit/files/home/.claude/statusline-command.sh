#!/bin/sh
input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // "Unknown Model"')
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
used_tokens=$(echo "$input" | jq -r '
  (.context_window.current_usage.input_tokens // 0) +
  (.context_window.current_usage.cache_creation_input_tokens // 0) +
  (.context_window.current_usage.cache_read_input_tokens // 0)
')
worktree=$(echo "$input" | jq -r '.worktree.name // empty')
current_dir=$(echo "$input" | jq -r '.worktree.original_cwd // empty')
rl_5h_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty' | awk '{printf "%.0f", $1}')
rl_5h_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
rl_7d_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
rl_7d_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

if [ -n "$used" ]; then
  used_display=$(printf "%.0f" "$used")
else
  used_display=0
fi

if [ -n "$used_tokens" ] && [ "$used_tokens" -gt 0 ]; then
  if [ "$used_tokens" -ge 1000 ]; then
    tokens_display=$(awk -v t="$used_tokens" 'BEGIN { printf "%.0fk", t/1000 }')
  else
    tokens_display="${used_tokens}"
  fi
else
  tokens_display=""
fi

if [ -n "$worktree" ]; then
  worktree_str="${worktree}"
else
  worktree_str="no worktree"
fi

GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
RESET='\033[0m'

git_str=""
if git rev-parse --git-dir >/dev/null 2>&1; then
  branch=$(git branch --show-current 2>/dev/null)
  [ -z "$branch" ] && branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  staged=$(git diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
  modified=$(git diff --numstat 2>/dev/null | wc -l | tr -d ' ')

  git_str="$branch"
  [ "$staged" -gt 0 ] && git_str="${git_str} $(printf "${GREEN}+${staged}${RESET}")"
  [ "$modified" -gt 0 ] && git_str="${git_str} $(printf "${YELLOW}~${modified}${RESET}")"
else
  git_str="no branch"
fi

make_bar() {
  pct="$1"
  width=10
  filled=$((pct * width / 100))
  empty=$((width - filled))
  bar=""
  i=0
  while [ $i -lt $filled ]; do
    bar="${bar}█"
    i=$((i + 1))
  done
  while [ $i -lt $width ]; do
    bar="${bar}░"
    i=$((i + 1))
  done
  printf "%s" "$bar"
}

format_rl() {
  pct="$1"
  reset_ts="$2"
  label="$3"
  [ -z "$pct" ] && return
  if [ "$pct" -ge 90 ]; then
    color="$RED"
  elif [ "$pct" -ge 70 ]; then
    color="$YELLOW"
  else
    color="$GREEN"
  fi
  reset_time=$(date -r "$reset_ts" "+%-I:%M%p" 2>/dev/null || date -d "@$reset_ts" "+%-I:%M%p" 2>/dev/null)
  bar=$(make_bar "$pct")
  printf "${color}${label} ${bar} ${pct}%% resets ${reset_time}${RESET}"
}

rate_limit_str=""
rate_limit_str="${rate_limit_str}$(format_rl "$rl_5h_pct" "$rl_5h_reset" "5h")"
# rate_limit_str="${rate_limit_str}$(format_rl "$rl_7d_pct" "$rl_7d_reset" "7d")"

if [ "$used_display" -ge 90 ]; then
  ctx_color="$RED"
elif [ "$used_display" -ge 70 ]; then
  ctx_color="$YELLOW"
else
  ctx_color="$GREEN"
fi
ctx_bar=$(make_bar "$used_display")
if [ -n "$tokens_display" ]; then
  usage_str=$(printf "${ctx_color}${ctx_bar} ${used_display}%% (${tokens_display})${RESET}")
else
  usage_str=$(printf "${ctx_color}${ctx_bar} ${used_display}%%${RESET}")
fi

repo_root=$(cd "$current_dir" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || echo "$current_dir")
dir_display=$(basename "$repo_root")
printf "🤖 %s | 🧠 %s | ⏱️ %s\n📁 %s | 🌳 %s | 🌿 %s" "$model" "$usage_str" "$rate_limit_str" "$dir_display" "$worktree_str" "$git_str"
