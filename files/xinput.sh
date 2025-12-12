#/usr/bin/env bash
set -euo pipefail

fc-cache -fv $XDG_DATA_HOME/fonts & disown
MOUSE=$(xinput | grep "Logitech USB Receiver Mouse" | awk -F'=' '{print $2}' | awk '{print $1}')
xinput set-prop "$MOUSE" "libinput Accel Profile Enabled" 0 1
xset r rate 210 66
