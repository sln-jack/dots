# Fix defaults
set -U fish_greeting ""
bind --erase --preset alt-e
# Vars
set -x TERM xterm-256color
set -x VISUAL nvim

# Hooks
starship init fish | .
direnv hook fish | .
zoxide init fish | .

alias ls="eza"
alias ll="eza -lh"
alias lla="eza -lah"
alias llt="eza -lah --sort time"
alias lt="eza -lTh"

abbr -a e nvim
abbr -a y yazi

abbr -a rsync rsync -Pavzr

abbr -a cc cargo check
abbr -a cb cargo build
abbr -a cbr cargo build -r
abbr -a cr cargo run --
abbr -a crb cargo run --bin 
abbr -a crr cargo run -r --
abbr -a crrb cargo run -r --bin

abbr -a g git
abbr -a gs git status
abbr -a gc git switch
abbr -a gcc git switch -c
abbr -a gcd git branch -D
abbr -a gba git branch -a
abbr -a gd git diff
abbr -a gds git diff --staged
abbr -a ga git add
abbr -a gr git reset --hard
abbr -a gr1 git reset --hard HEAD~1
abbr -a grs1 git reset --soft HEAD~1
abbr -a gf git pull
abbr -a gff git fetch
abbr -a gp git push
abbr -a gl git log
abbr -a gl1 git log -n1
abbr -a gl3 git log -n3
abbr -a gcm git commit -m
abbr -a gcf git commit --fixup
abbr -a gca git commit --amend --no-edit
abbr -a gcA git commit --amend
abbr -a gb git rebase
abbr -a gbi git rebase -i
abbr -a gbc git rebase --continue
abbr -a gu git restore --staged
abbr -a gy git stash
abbr -a gyu git stash -u
abbr -a gyp git stash pop
abbr -a gya git stash apply
abbr -a gyr git reset --merge
abbr -a gyl git stash list
abbr -a gys git stash show -p
abbr -a gwa git worktree add
abbr -a gwl git worktree list
abbr -a gwd git worktree remove

# Reload config
function reload
    ~/.dots/bootstrap.sh
    for config in ~/.config/fish/**/*.fish
        . $config
    end
end

# Open vim
function v
    set args '.'
    if test (count $argv) -gt 0
        set args $argv
    end
    setsid neovide --no-vsync $args >/dev/null 2>&1 &
end

# Make script
function mksh
    set file $argv[1]
    echo "#!/usr/bin/env bash" >> $file
    echo "set -euo pipefail" >> $file
    echo "" >> $file
    echo "" >> $file
    chmod +x $file
    nvim -c "normal! G" -c "startinsert" $file
end

# Find process
set ps_cols "pid,user,start,command"
function pg
    ps x -o $ps_cols | head -n1
    ps x -o $ps_cols | rg -v "rg $argv" | rg $argv
end
# Kill process
function pk
    ps x | rg -v "rg $argv" | rg $argv | awk '{print $1}' | xargs kill
end

function utc
    date +"%Y%m%d-%H:%M:%S.%6N"
end

function fish_user_key_bindings
    # Shift-{Tab,Enter}: accept autosuggestion {,and run}
    bind shift-tab   'commandline -f accept-autosuggestion'
    bind shift-enter 'commandline -f accept-autosuggestion execute'

    # Ctrl-Backspace/Del: delete word
    bind ctrl-delete    forward-kill-word
    bind ctrl-backspace backward-kill-word
    bind ctrl-h         backward-kill-word # Tmux
    # Colon: expand abbrs like space
    bind ':' 'commandline -f expand-abbr; commandline -i :'
end

# Start SSH agent
if test -z (pgrep ssh-agent)
  eval (ssh-agent -c)
  set -Ux SSH_AUTH_SOCK $SSH_AUTH_SOCK
  set -Ux SSH_AGENT_PID $SSH_AGENT_PID
  set -Ux SSH_AUTH_SOCK $SSH_AUTH_SOCK
end
