# Start SSH agent
set -gx SSH_AUTH_SOCK $XDG_RUNTIME_DIR/ssh-agent.sock
if not test -S $SSH_AUTH_SOCK
  pkill -U $USER ssh-agent 2>/dev/null
  ssh-agent -a $SSH_AUTH_SOCK -c 2>/dev/null | source
end
