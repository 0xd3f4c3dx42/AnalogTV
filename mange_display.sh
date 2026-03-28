#!/bin/bash

OSD_MATCH="fs42/osd/main.py"

kill_tree() {
    local pid="$1"
    local children

    [ -z "$pid" ] && return 0
    [ "$pid" = "0" ] && return 0
    [ "$pid" = "1" ] && return 0

    children=$(pgrep -P "$pid" 2>/dev/null || true)

    for child in $children; do
        kill_tree "$child"
    done

    kill "$pid" 2>/dev/null || true
    sleep 1
    kill -9 "$pid" 2>/dev/null || true
}

echo "Checking FieldStation42 OSD ..."

OSD_PIDS=$(pgrep -f "$OSD_MATCH" 2>/dev/null || true)

if [ -n "$OSD_PIDS" ]; then
    echo "Killing FieldStation42 OSD process and its parent ..."
    for pid in $OSD_PIDS; do
        parent=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
        if [ -n "$parent" ] && [ "$parent" != "0" ] && [ "$parent" != "1" ]; then
            kill_tree "$parent"
        fi
        kill_tree "$pid"
    done

    echo "Killing any leftover direct matches ..."
    pkill -f "$OSD_MATCH" 2>/dev/null || true
    pkill -9 -f "$OSD_MATCH" 2>/dev/null || true
else
    echo "FieldStation42 OSD is not running."
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
pgrep -af "$OSD_MATCH" || echo "No FieldStation42 OSD process found."
pgrep -a -x mpv || echo "No mpv process found."
