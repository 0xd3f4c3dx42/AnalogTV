#!/usr/bin/env bash
set -euo pipefail

# Change this if your folder name/path is different
cd "/home/analog/FieldStation42"

# Start OSD in the background
DISPLAY=:0 /home/analog/FieldStation42/env/bin/python3 fs42/osd/main.py &
OSD_PID=$!

# Let it run for 3 seconds
sleep 5

# Kill the OSD process
kill "$OSD_PID"

# Optional: wait for it to exit cleanly
wait "$OSD_PID" 2>/dev/null || true
