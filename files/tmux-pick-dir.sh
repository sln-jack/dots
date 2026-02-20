#!/bin/bash
# Cycle through existing directory paths in copy-mode. n/N to cycle.
# Test: echo "..." | CWD=/path ./tmux-pick-dir.sh test
if [[ "$1" == "test" ]]; then
    content=$(cat); cwd="${CWD:-.}"
else
    content=$(tmux capture-pane -p -S - -E -)
    cwd=$(tmux display -p '#{pane_current_path}')
fi

dirs=$(printf '%s\n' "$content" |
    grep -vE '^[0-9]{2}:[0-9]{2}:[0-9]{2}(am|pm) ' |
    tr -s '[:space:]' '\n' | sort -u |
    while IFS= read -r w; do
        if [[ "$w" == /* ]]; then [[ -d "$w" ]] && echo "$w"
        else [[ -d "$cwd/$w" ]] && echo "$w"
        fi
    done)

if [[ "$1" == "test" ]]; then echo "$dirs"; exit 0; fi
[[ -z "$dirs" ]] && { tmux display-message "No existing dirs found"; exit 0; }

regex=$(printf '%s\n' "$dirs" | sed 's/\./\\./g' | paste -sd'|' -)
[[ $(printf '%s\n' "$dirs" | wc -l) -gt 1 ]] && regex="($regex)"
regex="(^|[[:space:]])${regex}([[:space:]]|$)"
tmux send-keys -X "search-${1:-backward}" "$regex"
