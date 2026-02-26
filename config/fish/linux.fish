# Start SSH agent
if test -z (pgrep -U $USER ssh-agent)
  eval (ssh-agent -c 2>/dev/null)
  set -Ux SSH_AUTH_SOCK $SSH_AUTH_SOCK
  set -Ux SSH_AGENT_PID $SSH_AGENT_PID
end
