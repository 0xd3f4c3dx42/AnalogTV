#!/usr/bin/env bash
# Toggle a "blank" screen by changing mpv properties only.
# No wlr-randr, no display off. This just:
#   - sets brightness to -100 and mute=true (blank)
#   - or restores brightness to 0 and mute=false (unblank)
#
# Assumes mpv IPC socket is at /tmp/mpvsocket.

MPV_SOCKET="/tmp/mpvsocket"
STATE_FILE="/tmp/screen_blank_state"

send_mpv() {
    local json="$1"
    if [ -S "$MPV_SOCKET" ]; then
        echo "$json" | socat - "$MPV_SOCKET"
    else
        echo "Warning: mpv socket $MPV_SOCKET not found; command skipped: $json"
    fi
}

state="unblanked"
if [ -f "$STATE_FILE" ]; then
    state="$(cat "$STATE_FILE" 2>/dev/null || echo "unblanked")"
fi

if [ "$state" = "blanked" ]; then
    echo "Current state: BLANKED. Restoring normal brightness and audio..."
    # Restore brightness and unmute
    send_mpv '{ "command": ["set_property", "brightness", 0] }'
    send_mpv '{ "command": ["set_property", "mute", false] }'
    echo "unblanked" > "$STATE_FILE"
    echo "State is now UNBLANKED."
else
    echo "Current state: UNBLANKED. Forcing black image and muting audio..."
    # Force black by dropping brightness all the way, and mute audio
    send_mpv '{ "command": ["set_property", "brightness", -100] }'
    send_mpv '{ "command": ["set_property", "mute", true] }'
    echo "blanked" > "$STATE_FILE"
    echo "State is now BLANKED."
fi
