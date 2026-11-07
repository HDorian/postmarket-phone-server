#!/usr/bin/env python3
# Toggle the phone screen on each power-button *short* press.
# Reads the pwrkey evdev node directly (no external module) and runs screen-toggle.sh.
# Runs as root (event node is root:input; backlight writes need root).
import struct, subprocess, time, glob, sys

EV_KEY, KEY_POWER = 0x01, 116
FMT = "llHHi"                      # input_event on 64-bit: timeval(16) + type,code(u16) + value(i32)
SZ = struct.calcsize(FMT)
TOGGLE = "/usr/local/bin/screen-toggle.sh"

def find_pwrkey():
    # prefer the pm8941_pwrkey device; fall back to event0
    for ev in sorted(glob.glob("/sys/class/input/event*")):
        try:
            name = open(ev + "/device/name").read().strip()
        except OSError:
            continue
        if "pwrkey" in name or "pwr" in name.lower():
            return "/dev/input/" + ev.rsplit("/", 1)[1]
    return "/dev/input/event0"

def main():
    dev = find_pwrkey()
    last = 0.0
    with open(dev, "rb") as f:
        while True:
            data = f.read(SZ)
            if not data or len(data) < SZ:
                continue
            _sec, _usec, etype, code, val = struct.unpack(FMT, data)
            if etype == EV_KEY and code == KEY_POWER and val == 1:   # press
                now = time.time()
                if now - last < 0.4:     # debounce
                    continue
                last = now
                subprocess.run([TOGGLE], check=False)

if __name__ == "__main__":
    try:
        main()
    except (OSError, KeyboardInterrupt) as e:
        print("powerkey-listen:", e, file=sys.stderr)
        sys.exit(1)
