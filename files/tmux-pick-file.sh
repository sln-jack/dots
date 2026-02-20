#!/bin/bash
# Cycle through existing file paths in copy-mode. n/N to cycle.
# Test: echo "..." | CWD=/path ./tmux-pick-file.sh test
if [[ "$1" == "test" ]]; then
    content=$(cat); cwd="${CWD:-.}"
else
    content=$(tmux capture-pane -p -S - -E -)
    cwd=$(tmux display -p '#{pane_current_path}')
fi

paths=$(printf '%s\n' "$content" |
    grep -vE '^[0-9]{2}:[0-9]{2}:[0-9]{2}(am|pm) ' |
    tr -s '[:space:]' '\n' | sort -u |
    while IFS= read -r w; do
        if [[ "$w" == /* ]]; then [[ -f "$w" ]] && echo "$w"
        else [[ -f "$cwd/$w" ]] && echo "$w"
        fi
    done)

if [[ "$1" == "test" ]]; then echo "$paths"; exit 0; fi
[[ -z "$paths" ]] && { tmux display-message "No existing files found"; exit 0; }

regex=$(printf '%s\n' "$paths" | sed 's/\./\\./g' | paste -sd'|' -)
[[ $(printf '%s\n' "$paths" | wc -l) -gt 1 ]] && regex="($regex)"
tmux send-keys -X "search-${1:-backward}" "$regex"
