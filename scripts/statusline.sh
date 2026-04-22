#!/usr/bin/env bash

input=$(cat)

abbrev() {
  local n="$1"
  if [ -z "$n" ] || [ "$n" = "null" ]; then echo "0"; return; fi
  awk -v n="$n" 'BEGIN {
    if (n >= 1000000) printf "%.1fM", n/1000000
    else if (n >= 1000) printf "%.1fk", n/1000
    else printf "%d", n
  }'
}

model=$(echo "$input" | jq -r '.model.display_name // empty')
cwd=$(echo "$input"   | jq -r '.workspace.current_dir // .cwd // empty')
folder=$(basename "$cwd")

total_in=$(echo "$input"  | jq -r '.context_window.total_input_tokens  // 0')
total_out=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')
total_tokens=$(( total_in + total_out ))

MAX_TOKENS=1000000
BAR_LEN=10
filled=$(( total_tokens * BAR_LEN / MAX_TOKENS ))
[ "$filled" -gt "$BAR_LEN" ] && filled=$BAR_LEN
[ "$filled" -lt 0 ] && filled=0
empty=$(( BAR_LEN - filled ))

if   [ "$total_tokens" -ge 500000 ]; then color=$'\033[31m'
elif [ "$total_tokens" -ge 100000 ]; then color=$'\033[33m'
else                                      color=$'\033[32m'
fi
reset=$'\033[0m'

bar=""
for ((i=0; i<filled; i++)); do bar+="▰"; done
for ((i=0; i<empty;  i++)); do bar+="▱"; done

token_str=$(abbrev "$total_tokens")

parts=()
[ -n "$model" ]  && parts+=("$model")
[ -n "$folder" ] && parts+=("$folder")
parts+=("${color}${bar}${reset} ${token_str}")

result=""
sep=" · "
for part in "${parts[@]}"; do
  if [ -z "$result" ]; then
    result="$part"
  else
    result="${result}${sep}${part}"
  fi
done

printf "%s\n" "$result"
