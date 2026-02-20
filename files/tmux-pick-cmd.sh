#!/bin/bash
cmds=$(tmux capture-pane -p -S - -E - | sed -nE 's/^[0-9]{2}:[0-9]{2}:[0-9]{2}(am|pm) [^>]+> (.*[^[:space:]]).*/\2/p' | awk '!seen[$0]++')
[[ -z "$cmds" ]] && exit 0
regex=$(printf '%s\n' "$cmds" | sed 's/\./\\./g' | paste -sd'|' -)
tmux send-keys -X "search-${1:-backward}" "($regex)"
