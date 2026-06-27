#!/usr/bin/env bash
xrandr --output DP-0 --left-of HDMI-0 --mode 3840x2160 --rate 144
xrandr --output DP-2 --right-of HDMI-0 --mode 3840x2160 --rate 144
xrandr --output HDMI-0 --mode 3840x2160 --rate 144
