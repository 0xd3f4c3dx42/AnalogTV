#!/usr/bin/env python3
import os
import time
import json
import subprocess
from pathlib import Path

# Force a safe working directory for lgpio's temp files.
# This must run BEFORE importing lgpio / LGPIOFactory.
os.chdir("/tmp")
print("[gpioButtons] cwd at startup:", os.getcwd())

from gpiozero import Button, Device
from gpiozero.pins.lgpio import LGPIOFactory

# Use the modern lgpio backend
Device.pin_factory = LGPIOFactory()

# --- Paths ---
FS_ROOT = Path("/home/analog/FieldStation42")
SOCKET = FS_ROOT / "runtime" / "channel.socket"
STATUS_FILE = FS_ROOT / "runtime" / "play_status.socket"

# Path to helper scripts + env python
ENV_PYTHON = FS_ROOT / "env" / "bin" / "python3"
BLANK_SCRIPT = FS_ROOT / "scripts" / "blankDisplay.py"
SETDISPLAY_SCRIPT = FS_ROOT / "scripts" / "setDisplayText.py"

# Static payloads for up/down
PAYLOADS = {
    "up":   '{"command": "up", "channel": -1}\n',
    "down": '{"command": "down", "channel": -1}\n',
}

# Guide channel
GUIDE_CHANNEL = 13

# State for guide button behavior
guide_pressed_at = None
guide_shutdown_triggered = False
guide_last_display = "    "
guide_current_countdown = None

GUIDE_HOLD_SECONDS = 2.5      # how long to hold to shutdown
GUIDE_TAP_MAX_SECONDS = 0.5   # <= this is a "normal" tap to guide


def get_last_display_string() -> str:
    """
    Approximate the last channel shown on the display by reading
    runtime/play_status.socket like channelDisplay.py does.
    """
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


def set_display(text: str) -> None:
    """Set the 4-digit display text via the helper script."""
    text = (text or "    ")[:4]
    try:
        if not ENV_PYTHON.exists():
            print(f"[gpioButtons] Env python not found at {ENV_PYTHON}")
            return
        if not SETDISPLAY_SCRIPT.exists():
            print(f"[gpioButtons] setDisplayText script not found at {SETDISPLAY_SCRIPT}")
            return

        print(f"[gpioButtons] Setting display to '{text}'")
        subprocess.run(
            [str(ENV_PYTHON), str(SETDISPLAY_SCRIPT), text],
            check=False,
        )
    except Exception as e:
        print(f"[gpioButtons] Failed to set display: {e}")


def run_blank_display() -> None:
    """Run blankDisplay.py to stop the channel display and blank the LCD."""
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


def send_command(cmd: str) -> None:
    """Write the appropriate JSON payload into channel.socket."""
    if cmd == "guide":
        # Fixed channel 12 for guide
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


def shutdown_system() -> None:
    """Trigger a clean system shutdown when Guide has been held long enough."""
    global guide_shutdown_triggered
    if guide_shutdown_triggered:
        return

    guide_shutdown_triggered = True
    print(f"[gpioButtons] Guide held for {GUIDE_HOLD_SECONDS:.0f}s: "
          "blanking LCD and shutting down...")

    # 1) Blank the LCD via your existing helper
    run_blank_display()

    # 2) Power off the system
    try:
        subprocess.Popen(["/bin/systemctl", "poweroff"])
    except Exception as e:
        print(f"[gpioButtons] Failed to shutdown: {e}")


def on_guide_pressed() -> None:
    """Handle initial Guide press: start tracking time and remember display."""
    global guide_pressed_at, guide_shutdown_triggered, guide_last_display, guide_current_countdown

    guide_pressed_at = time.monotonic()
    guide_shutdown_triggered = False
    guide_current_countdown = None
    guide_last_display = get_last_display_string()
    print("[gpioButtons] Guide pressed")


def on_guide_released() -> None:
    """
    Handle Guide release:

    - <= GUIDE_TAP_MAX_SECONDS: quick tap → normal guide behavior
    - between tap_max and hold_seconds: abort shutdown → restore last display
    - >= hold_seconds: shutdown is already in progress
    """
    global guide_pressed_at, guide_shutdown_triggered, guide_current_countdown

    if guide_shutdown_triggered:
        print("[gpioButtons] Guide released after shutdown started, ignoring")
        return

    if guide_pressed_at is None:
        print("[gpioButtons] Guide released with no press timestamp")
        return

    held_for = time.monotonic() - guide_pressed_at
    print(f"[gpioButtons] Guide released after {held_for:.2f}s")

    # Reset hold-tracking state
    guide_pressed_at = None
    guide_current_countdown = None

    if held_for <= GUIDE_TAP_MAX_SECONDS:
        # Quick tap: normal guide behavior → fixed channel 12
        print("[gpioButtons] Guide tap: sending guide command (channel 12)")
        send_command("guide")
    elif held_for < GUIDE_HOLD_SECONDS:
        # Held long enough to show countdown but not long enough to shutdown: abort
        print("[gpioButtons] Guide hold aborted; restoring last channel display")
        set_display(guide_last_display)
    else:
        # Held long enough to trigger shutdown; shutdown_system() should already be running
        print("[gpioButtons] Guide released after shutdown threshold; nothing to do")


def update_guide_state() -> None:
    """Update countdown state while Guide is being held."""
    global guide_current_countdown, guide_pressed_at

    if guide_pressed_at is None or guide_shutdown_triggered:
        return

    held_for = time.monotonic() - guide_pressed_at

    if held_for >= GUIDE_HOLD_SECONDS:
        shutdown_system()
        return

    # Only show countdown after we've passed the "tap" window
    if held_for <= GUIDE_TAP_MAX_SECONDS:
        return

    remaining = GUIDE_HOLD_SECONDS - held_for
    # 3 -> 2 -> 1 as time passes
    countdown = max(1, int(remaining + 0.9999))

    if countdown != guide_current_countdown:
        guide_current_countdown = countdown
        # Show the countdown number right-aligned, e.g. "   3"
        set_display(f"   {countdown}")


def main():
    # BCM numbers: 19 (pin 35), 16 (pin 36), 20 (pin 38)
    btn_up = Button(19, pull_up=True, bounce_time=0.05)
    btn_down = Button(16, pull_up=True, bounce_time=0.05)
    btn_guide = Button(20, pull_up=True, bounce_time=0.05)

    # Up/Down fire on press
    btn_up.when_pressed = lambda: send_command("up")
    btn_down.when_pressed = lambda: send_command("down")

    # Guide uses custom press/hold/release logic
    btn_guide.when_pressed = on_guide_pressed
    btn_guide.when_released = on_guide_released

    print(
        "[gpioButtons] Ready. Up/Down = channel nav, "
        "Guide tap = channel 12, "
        "hold Guide to see countdown, hold for 3s = blank + shutdown, "
        "release early = restore channel."
    )

    try:
        while True:
            update_guide_state()
            time.sleep(0.1)
    except KeyboardInterrupt:
        print("\n[gpioButtons] Exiting.")


if __name__ == "__main__":
    main()
