#!/usr/bin/env python3
import os
import time
import subprocess
from pathlib import Path

from evdev import InputDevice, categorize, ecodes

# Path to the Flirc keyboard device (from: ls -l /dev/input/by-id | grep flirc)
DEVICE_PATH = "/dev/input/by-id/usb-flirc.tv_flirc-if01-event-kbd"

# Project paths
FS_ROOT = Path("/home/analog/FieldStation42")
SOCKET = FS_ROOT / "runtime" / "channel.socket"

# Paths to helper scripts
SCREEN_TOGGLE_SCRIPT = FS_ROOT / "scripts" / "screenToggle.sh"
OSD_SCRIPT = FS_ROOT / "scripts" / "OSD.sh"

# JSON payloads to send into channel.socket
PAYLOADS = {
    "up":    '{"command": "up", "channel": -1}\n',
    "down":  '{"command": "down", "channel": -1}\n',
    "guide": '{"command": "direct", "channel": 13}\n',
}

# Map keycodes from Flirc to command names above
# "screen_toggle" and "osd" are handled separately (not written to channel.socket)
KEYMAP = {
    "KEY_UP":      "up",
    "KEY_DOWN":    "down",
    "KEY_HOME":    "guide",         # guide/home button -> channel 13
    "KEY_ESC":     "screen_toggle", # Escape key toggles screen via screenToggle.sh
    "KEY_SPACE":   "osd",           # Space key runs OSD.sh
    # Add more mappings here if needed
}


def send_command(cmd: str) -> None:
    """Write the appropriate JSON payload into channel.socket."""
    payload = PAYLOADS.get(cmd)
    if payload is None:
        print(f"[remoteListener] Unknown command: {cmd}")
        return

    if not SOCKET.exists():
        print(f"[remoteListener] Socket {SOCKET} does not exist")
        return

    try:
        with SOCKET.open("w", encoding="utf-8") as f:
            f.write(payload)
        print(f"[remoteListener] Sent {cmd}: {payload.strip()}")
    except OSError as e:
        print(f"[remoteListener] Error writing to {SOCKET}: {e}")


def _run_script(script_path: Path, label: str) -> None:
    """Run an external shell script if it exists and is executable."""
    if not script_path.exists():
        print(f"[remoteListener] {label} script not found at {script_path}")
        return

    if not os.access(script_path, os.X_OK):
        print(f"[remoteListener] {label} script not executable: {script_path}")
        return

    try:
        print(f"[remoteListener] Running {label} script: {script_path}")
        subprocess.Popen([str(script_path)])
    except Exception as e:
        print(f"[remoteListener] Failed to run {label} script: {e}")


def run_screen_toggle() -> None:
    """Run the screen toggle script."""
    _run_script(SCREEN_TOGGLE_SCRIPT, "screen toggle")


def run_osd() -> None:
    """Run the OSD script."""
    _run_script(OSD_SCRIPT, "OSD")


def open_device() -> InputDevice:
    """Block until the Flirc device is available, then return an InputDevice."""
    while True:
        try:
            dev = InputDevice(DEVICE_PATH)
            print(f"[remoteListener] Opened device: {DEVICE_PATH}")
            return dev
        except FileNotFoundError:
            print(f"[remoteListener] {DEVICE_PATH} not found, retrying in 2s...")
            time.sleep(2)


def event_loop() -> None:
    """Main loop: read events from Flirc and translate to commands or helper scripts."""
    while True:
        dev = open_device()
        try:
            for event in dev.read_loop():
                if event.type != ecodes.EV_KEY:
                    continue

                key_event = categorize(event)

                # Only act on key-down, ignore key-up/repeat
                if key_event.keystate != key_event.key_down:
                    continue

                keycode = key_event.keycode
                if isinstance(keycode, list):
                    keycode = keycode[0]

                cmd = KEYMAP.get(keycode)
                if not cmd:
                    continue

                print(f"[remoteListener] Key {keycode} -> command {cmd}")

                if cmd == "screen_toggle":
                    run_screen_toggle()
                elif cmd == "osd":
                    run_osd()
                else:
                    send_command(cmd)
        except OSError as e:
            # Device disconnected or some read error; loop back and reopen
            print(f"[remoteListener] Device error: {e}, reopening in 2s...")
            time.sleep(2)


def main():
    print(f"[remoteListener] Starting Flirc listener on {DEVICE_PATH}")
    try:
        event_loop()
    except KeyboardInterrupt:
        print("\n[remoteListener] Exiting.")


if __name__ == "__main__":
    main()
