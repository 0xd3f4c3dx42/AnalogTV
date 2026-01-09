#!/usr/bin/env python3
"""
Blank the TM1637 channel display by writing four spaces.

Stops the channelDisplay systemd service first so nothing else
is trying to update the display at the same time.
"""

import subprocess
import time
import tm1637

# Systemd service name running channelDisplay.py
SERVICE_NAME = "channelDisplay.service"

# TM1637 pins (BCM numbers) – same as channelDisplay.py
CLK = 26  # physical pin 37
DIO = 21  # physical pin 40


def main():
    # 1) Stop the channel display service so it stops updating the display
    try:
        print(f"[blankDisplay] Stopping {SERVICE_NAME}...")
        subprocess.run(
            ["/bin/systemctl", "stop", SERVICE_NAME],
            check=False,
        )
        # Small delay to let it actually stop
        time.sleep(0.3)
    except Exception as e:
        print(f"[blankDisplay] Failed to stop {SERVICE_NAME}: {e}")

    # 2) Create the display instance and blank it
    display = tm1637.TM1637(clk=CLK, dio=DIO)
    disp_str = "    "  # four spaces
    display.show(disp_str)
    print(f"[blankDisplay] Display blanked to {repr(disp_str)}")


if __name__ == "__main__":
    main()
