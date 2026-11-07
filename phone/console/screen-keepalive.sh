#!/bin/sh
# Re-assert the screen ON if it slept on its own — but NOT if the user turned it off with the
# power button (that leaves /run/screen.off). Run minutely from cron. No-op when already on,
# so there's no flicker.
[ -f /run/screen.off ] && exit 0
BL=/sys/class/backlight/c994000.dsi.0
# already on? do nothing
if [ "$(cat "$BL/bl_power" 2>/dev/null)" = "0" ] && [ "$(cat "$BL/brightness" 2>/dev/null)" != "0" ]; then
  exit 0
fi
echo 0 > "$BL/bl_power" 2>/dev/null
echo "$(cat "$BL/max_brightness" 2>/dev/null || echo 1023)" > "$BL/brightness" 2>/dev/null
printf '\033[9;0]' > /dev/tty1 2>/dev/null   # keep console blank timer disabled
exit 0
