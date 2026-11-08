#!/usr/bin/env python3
# Power button on the phone:
#   short press (release < HOLD) -> toggle the screen
#   hold (>= HOLD seconds)       -> clean poweroff ("close the phone")
# Reads the pwrkey evdev node directly (no external module). Runs as root (event node is
# root:input; backlight writes + poweroff need root).
import os, struct, select, subprocess, time, glob, sys

EV_KEY, KEY_POWER = 0x01, 116
FMT = "llHHi"                      # input_event (64-bit): timeval(16) + type,code(u16) + value(i32)
SZ = struct.calcsize(FMT)
TOGGLE = "/usr/local/bin/screen-toggle.sh"
POWEROFF = "/sbin/poweroff"
HOLD = 2.5                         # seconds held -> shut down
DEBOUNCE = 0.3

def find_pwrkey():
    for ev in sorted(glob.glob("/sys/class/input/event*")):
        try:
            name = open(ev + "/device/name").read().strip()
        except OSError:
            continue
        if "pwr" in name.lower():
            return "/dev/input/" + ev.rsplit("/", 1)[1]
    return "/dev/input/event0"

def read_event(fd):
    data = os.read(fd, SZ)
    if len(data) < SZ:
        return None
    _s, _u, etype, code, val = struct.unpack(FMT, data)
    return (etype, code, val)

def main():
    fd = os.open(find_pwrkey(), os.O_RDONLY)
    pressed_at = None
    last_toggle = 0.0
    while True:
        if pressed_at is None:
            ev = read_event(fd)                       # block until an event
            if ev == (EV_KEY, KEY_POWER, 1):          # key down
                pressed_at = time.time()
            continue
        # key is down: short press if released before HOLD, else power off
        remaining = HOLD - (time.time() - pressed_at)
        if remaining <= 0:
            subprocess.run([POWEROFF], check=False)
            pressed_at = None
            continue
        r, _, _ = select.select([fd], [], [], remaining)
        if r:
            ev = read_event(fd)
            if ev and ev[0] == EV_KEY and ev[1] == KEY_POWER and ev[2] == 0:   # released in time
                now = time.time()
                if now - last_toggle >= DEBOUNCE:
                    last_toggle = now
                    subprocess.run([TOGGLE], check=False)
                pressed_at = None
            # SYN / autorepeat / other codes: ignore, keep timing the hold
        else:
            subprocess.run([POWEROFF], check=False)   # still held at HOLD -> shut down
            pressed_at = None

if __name__ == "__main__":
    try:
        main()
    except (OSError, KeyboardInterrupt) as e:
        print("powerkey-listen:", e, file=sys.stderr)
        sys.exit(1)
