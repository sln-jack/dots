# Start SSH agent
set -gx SSH_AUTH_SOCK /run/user/(id -u)/ssh-agent.sock
if not pgrep -U $USER ssh-agent > /dev/null
  ssh-agent -a $SSH_AUTH_SOCK > /dev/null
end
