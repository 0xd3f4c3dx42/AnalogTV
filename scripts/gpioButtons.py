#!/usr/bin/env python3
import json
import os
import subprocess
import time
from pathlib import Path

# Force a safe working directory for lgpio temp files.
os.chdir("/tmp")
print("[gpioButtons] cwd at startup:", os.getcwd())

from gpiozero import Button, Device
from gpiozero.pins.lgpio import LGPIOFactory

Device.pin_factory = LGPIOFactory()

# --- Paths ---
FS_ROOT = Path("/home/analog/FieldStation42")
SOCKET = FS_ROOT / "runtime" / "channel.socket"
STATUS_FILE = FS_ROOT / "runtime" / "play_status.socket"

ENV_PYTHON = FS_ROOT / "env" / "bin" / "python3"
BLANK_SCRIPT = FS_ROOT / "scripts" / "blankDisplay.py"
SETDISPLAY_SCRIPT = FS_ROOT / "scripts" / "setDisplayText.py"

# Static payloads for up/down
PAYLOADS = {
    "up": '{"command": "up", "channel": -1}\n',
    "down": '{"command": "down", "channel": -1}\n',
}

# Guide channel
GUIDE_CHANNEL = 21

# Guide button behavior
guide_pressed_at = None
guide_shutdown_triggered = False
guide_last_display = "    "
guide_current_countdown = None

GUIDE_HOLD_SECONDS = 2.5
GUIDE_TAP_MAX_SECONDS = 0.5

# Rebuild button multi-click behavior
REBUILD_CLICK_WINDOW = 0.6
rebuild_click_count = 0
rebuild_last_press_time = 0.0
rebuild_triggered = False


def get_last_display_string():
    try:
        if not STATUS_FILE.exists():
            print(f"[gpioButtons] Status file not found: {STATUS_FILE}")
            return "    "

        with STATUS_FILE.open("r", encoding="utf-8") as f:
            data = json.load(f)

        channel_num = data.get("channel_number")
        if channel_num is None:
            return "    "

        ch = int(channel_num)
        disp_str = f"Ch0{ch}" if ch < 10 else f"Ch{ch}"
        disp_str = disp_str[:4]
        print(f"[gpioButtons] Remembering last display as '{disp_str}'")
        return disp_str

    except Exception as e:
        print(f"[gpioButtons] Error reading {STATUS_FILE}: {e}")
        return "    "


def set_display(text):
    text = (text or "    ")[:4]
    try:
        if not ENV_PYTHON.exists():
            print(f"[gpioButtons] Env python not found at {ENV_PYTHON}")
            return
        if not SETDISPLAY_SCRIPT.exists():
            print(
                f"[gpioButtons] setDisplayText script not found at {SETDISPLAY_SCRIPT}"
            )
            return

        print(f"[gpioButtons] Setting display to '{text}'")
        subprocess.run(
            [str(ENV_PYTHON), str(SETDISPLAY_SCRIPT), text],
            check=False,
        )
    except Exception as e:
        print(f"[gpioButtons] Failed to set display: {e}")


def run_blank_display():
    try:
        if not ENV_PYTHON.exists():
            print(f"[gpioButtons] Env python not found at {ENV_PYTHON}")
            return
        if not BLANK_SCRIPT.exists():
            print(f"[gpioButtons] Blank script not found at {BLANK_SCRIPT}")
            return

        print("[gpioButtons] Running blankDisplay.py to blank the LCD...")
        subprocess.run(
            [str(ENV_PYTHON), str(BLANK_SCRIPT)],
            check=False,
        )
    except Exception as e:
        print(f"[gpioButtons] Failed to run blankDisplay.py: {e}")


def run_station42(args):
    try:
        if not ENV_PYTHON.exists():
            print(f"[gpioButtons] Env python not found at {ENV_PYTHON}")
            return

        subprocess.run(
            [str(ENV_PYTHON), "station_42.py"] + args,
            cwd=str(FS_ROOT),
            check=False,
        )
    except Exception as e:
        print(f"[gpioButtons] Failed to run station_42.py {' '.join(args)}: {e}")


def send_command(cmd):
    if cmd == "guide":
        payload = f'{{"command": "direct", "channel": {GUIDE_CHANNEL}}}\n'
    else:
        payload = PAYLOADS.get(cmd)

    if payload is None:
        print(f"[gpioButtons] Unknown command: {cmd}")
        return

    if not SOCKET.exists():
        print(f"[gpioButtons] Socket {SOCKET} does not exist")
        return

    try:
        with SOCKET.open("w", encoding="utf-8") as f:
            f.write(payload)
        print(f"[gpioButtons] Sent {cmd}: {payload.strip()}")
    except OSError as e:
        print(f"[gpioButtons] Error writing to {SOCKET}: {e}")


def shutdown_system():
    global guide_shutdown_triggered
    if guide_shutdown_triggered:
        return

    guide_shutdown_triggered = True
    print(
        f"[gpioButtons] Guide held for {GUIDE_HOLD_SECONDS:.1f}s: blanking LCD and shutting down..."
    )

    run_blank_display()

    try:
        subprocess.Popen(["/bin/systemctl", "poweroff"])
    except Exception as e:
        print(f"[gpioButtons] Failed to shutdown: {e}")


def trigger_rebuild_month_reboot():
    global rebuild_triggered
    if rebuild_triggered:
        return

    rebuild_triggered = True
    print("[gpioButtons] Rebuild button double-click detected.")
    print("[gpioButtons] Running rebuild: station_42.py -r")
    run_station42(["-r"])

    print("[gpioButtons] Adding month: station_42.py -m")
    run_station42(["-m"])

    print("[gpioButtons] Rebooting now...")
    try:
        subprocess.Popen(["/bin/systemctl", "reboot"])
    except Exception as e:
        print(f"[gpioButtons] Failed to reboot: {e}")


def trigger_reboot_only():
    global rebuild_triggered
    if rebuild_triggered:
        return

    rebuild_triggered = True
    print("[gpioButtons] Rebuild button 4-click detected. Rebooting now...")
    try:
        subprocess.Popen(["/bin/systemctl", "reboot"])
    except Exception as e:
        print(f"[gpioButtons] Failed to reboot: {e}")


def on_rebuild_pressed():
    global rebuild_click_count, rebuild_last_press_time, rebuild_triggered

    if rebuild_triggered:
        return

    rebuild_click_count += 1
    rebuild_last_press_time = time.monotonic()
    print(f"[gpioButtons] Rebuild button press count: {rebuild_click_count}")


def update_rebuild_state():
    global rebuild_click_count, rebuild_last_press_time

    if rebuild_triggered or rebuild_click_count == 0:
        return

    elapsed = time.monotonic() - rebuild_last_press_time
    if elapsed < REBUILD_CLICK_WINDOW:
        return

    count = rebuild_click_count
    rebuild_click_count = 0

    if count >= 4:
        trigger_reboot_only()
    elif count >= 2:
        trigger_rebuild_month_reboot()
    else:
        print("[gpioButtons] Single rebuild-button press ignored")


def on_guide_pressed():
    global \
        guide_pressed_at, \
        guide_shutdown_triggered, \
        guide_last_display, \
        guide_current_countdown

    guide_pressed_at = time.monotonic()
    guide_shutdown_triggered = False
    guide_current_countdown = None
    guide_last_display = get_last_display_string()
    print("[gpioButtons] Guide pressed")


def on_guide_released():
    global guide_pressed_at, guide_shutdown_triggered, guide_current_countdown

    if guide_shutdown_triggered:
        print("[gpioButtons] Guide released after shutdown started, ignoring")
        return

    if guide_pressed_at is None:
        print("[gpioButtons] Guide released with no press timestamp")
        return

    held_for = time.monotonic() - guide_pressed_at
    print(f"[gpioButtons] Guide released after {held_for:.2f}s")

    guide_pressed_at = None
    guide_current_countdown = None

    if held_for <= GUIDE_TAP_MAX_SECONDS:
        print(
            f"[gpioButtons] Guide tap: sending guide command (channel {GUIDE_CHANNEL})"
        )
        send_command("guide")
    elif held_for < GUIDE_HOLD_SECONDS:
        print("[gpioButtons] Guide hold aborted; restoring last channel display")
        set_display(guide_last_display)
    else:
        print("[gpioButtons] Guide released after shutdown threshold; nothing to do")


def update_guide_state():
    global guide_current_countdown, guide_pressed_at

    if guide_pressed_at is None or guide_shutdown_triggered:
        return

    held_for = time.monotonic() - guide_pressed_at

    if held_for >= GUIDE_HOLD_SECONDS:
        shutdown_system()
        return

    if held_for <= GUIDE_TAP_MAX_SECONDS:
        return

    remaining = GUIDE_HOLD_SECONDS - held_for
    countdown = max(1, int(remaining + 0.9999))

    if countdown != guide_current_countdown:
        guide_current_countdown = countdown
        set_display(f"   {countdown}")


def main():
    # BCM numbers:
    # Up      -> GPIO19 (physical pin 35)
    # Down    -> GPIO16 (physical pin 36)
    # Guide   -> GPIO20 (physical pin 38)
    # Rebuild -> GPIO18 (physical pin 12)
    btn_up = Button(19, pull_up=True, bounce_time=0.05)
    btn_down = Button(16, pull_up=True, bounce_time=0.05)
    btn_guide = Button(20, pull_up=True, bounce_time=0.05)
    btn_rebuild = Button(18, pull_up=True, bounce_time=0.05)

    btn_up.when_pressed = lambda: send_command("up")
    btn_down.when_pressed = lambda: send_command("down")

    btn_guide.when_pressed = on_guide_pressed
    btn_guide.when_released = on_guide_released

    btn_rebuild.when_pressed = on_rebuild_pressed

    print(
        "[gpioButtons] Ready. Up/Down = channel nav, "
        f"Guide tap = channel {GUIDE_CHANNEL}, "
        f"hold Guide {GUIDE_HOLD_SECONDS:.1f}s = blank + shutdown, "
        "release early = restore channel, "
        "Rebuild button: 2 clicks = rebuild + month + reboot, "
        "4 clicks = reboot only."
    )

    try:
        while True:
            update_guide_state()
            update_rebuild_state()
            time.sleep(0.1)
    except KeyboardInterrupt:
        print("\n[gpioButtons] Exiting.")


if __name__ == "__main__":
    main()
