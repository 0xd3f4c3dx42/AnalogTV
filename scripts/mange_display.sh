#!/bin/bash

SERVICE="channelDisplay.service"
CHANNEL_SCRIPT="/home/analog/FieldStation42/scripts/channelDisplay.py"
FIELDSTATION_ROOT="/home/analog/FieldStation42"

kill_tree() {
    local pid="$1"
    local children

    children=$(pgrep -P "$pid" 2>/dev/null || true)

    for child in $children; do
        kill_tree "$child"
    done

    kill "$pid" 2>/dev/null || true
    sleep 1
    kill -9 "$pid" 2>/dev/null || true
}

echo "Checking $SERVICE ..."

if systemctl is-active --quiet "$SERVICE"; then
    echo "$SERVICE is running. Capturing related PIDs..."

    ROOT_PIDS=$(pgrep -f "$CHANNEL_SCRIPT" 2>/dev/null || true)

    echo "Stopping $SERVICE ..."
    sudo systemctl stop "$SERVICE" 2>/dev/null || true
    sudo systemctl kill --kill-who=all "$SERVICE" 2>/dev/null || true
    sleep 1
    sudo systemctl kill -s SIGKILL --kill-who=all "$SERVICE" 2>/dev/null || true

    if [ -n "$ROOT_PIDS" ]; then
        echo "Killing channelDisplay.py process tree ..."
        for pid in $ROOT_PIDS; do
            kill_tree "$pid"
        done
    fi

    echo "Killing any leftover FieldStation42 processes ..."
    pkill -f "$CHANNEL_SCRIPT" 2>/dev/null || true
    pkill -9 -f "$CHANNEL_SCRIPT" 2>/dev/null || true
    pkill -f "$FIELDSTATION_ROOT" 2>/dev/null || true
    pkill -9 -f "$FIELDSTATION_ROOT" 2>/dev/null || true

else
    echo "$SERVICE is not running. Starting it ..."
    sudo systemctl start "$SERVICE"
fi

echo
echo "Checking mpv ..."

if pgrep -x mpv >/dev/null; then
    echo "mpv is running. Stopping it ..."
    pkill -x mpv 2>/dev/null || true
    sleep 1
    pkill -9 -x mpv 2>/dev/null || true
else
    echo "mpv is not running."
    read -rp "Reboot now? [y/N]: " answer
    case "$answer" in
        [Yy]|[Yy][Ee][Ss])
            echo "Rebooting ..."
            sudo reboot
            ;;
        *)
            echo "Reboot cancelled."
            ;;
    esac
fi

echo
echo "Remaining matches:"
systemctl is-active "$SERVICE" || true
pgrep -af "$CHANNEL_SCRIPT" || echo "No channelDisplay.py process found."
pgrep -af "$FIELDSTATION_ROOT" || echo "No leftover FieldStation42 process found."
pgrep -a -x mpv || echo "No mpv process found."
