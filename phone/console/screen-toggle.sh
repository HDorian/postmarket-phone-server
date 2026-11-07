#!/bin/sh
# Toggle the phone's AMOLED panel on/off. State tracked in a file (hardware reads are unreliable
# across DPMS). Called by the power-key listener; also runnable over SSH to force a state:
#   screen-toggle.sh on | off | toggle   (default: toggle)
BL=/sys/class/backlight/c994000.dsi.0
STATE=/run/screen.off
MAX=$(cat "$BL/max_brightness" 2>/dev/null || echo 1023)

on(){  echo 0   > "$BL/bl_power"   2>/dev/null; echo "$MAX" > "$BL/brightness" 2>/dev/null; rm -f "$STATE"; }
off(){ echo 0   > "$BL/brightness" 2>/dev/null; echo 4    > "$BL/bl_power"   2>/dev/null; : > "$STATE"; }

case "${1:-toggle}" in
  on)  on ;;
  off) off ;;
  *)   if [ -f "$STATE" ]; then on; else off; fi ;;
esac
