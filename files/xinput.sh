#!/usr/bin/env bash

fc-cache -f "$XDG_DATA_HOME/fonts" & disown

xset r rate 210 66
xset -dpms
xset s off

# Mouse accel (evdev driver). Skip if no mouse attached.
MOUSE=$(xinput 2>/dev/null | grep -i "Logitech USB Receiver Mouse" | awk -F'=' '{print $2}' | awk '{print $1}') || true
if [ -n "${MOUSE:-}" ]; then
    xinput set-prop "$MOUSE" "Device Accel Profile" 0 || true
fi
