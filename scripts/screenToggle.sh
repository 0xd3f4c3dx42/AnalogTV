#!/bin/bash

# Fast FieldStation42 composite video/audio toggle for Raspberry Pi OS + labwc.
# Uses absolute system binaries so Conda/venv does not affect operation.
#
# OFF: mute -> stop FieldStation42 OSD -> remember whether kanshi was running -> stop kanshi -> wlopm off
# ON:  wlopm on -> if KMS has no CRTC, immediately VT-bounce -> verify -> unmute
#      -> restart FieldStation42 OSD -> restart kanshi only if it was running before OFF.

set -u

OUTPUT="${OUTPUT:-Composite-1}"
STATE_FILE="/tmp/fieldstation42-composite-toggle.state"
LOG_PREFIX="[screenToggle]"

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

log() {
    echo "$LOG_PREFIX $*"
}

have() {
    [ -x "$1" ]
}

# -----------------------------------------------------------------------------
# Find active Wayland session
# -----------------------------------------------------------------------------
GUI_USER=""
GUI_UID=""
GUI_HOME=""
XDG_RUNTIME_DIR=""
WAYLAND_DISPLAY=""
GUI_SESSION=""
GUI_VT=""

find_wayland_socket() {
    runtime="$1"
    for p in "$runtime"/wayland-*; do
        [ -S "$p" ] || continue
        /usr/bin/basename "$p"
        return 0
    done
    return 1
}

try_user_runtime() {
    user="$1"
    [ -n "$user" ] || return 1

    uid=$(/usr/bin/id -u "$user" 2>/dev/null) || return 1
    runtime="/run/user/$uid"
    [ -d "$runtime" ] || return 1

    wd=$(find_wayland_socket "$runtime") || return 1
    home=$(/usr/bin/getent passwd "$user" | /usr/bin/cut -d: -f6)

    GUI_USER="$user"
    GUI_UID="$uid"
    GUI_HOME="$home"
    XDG_RUNTIME_DIR="$runtime"
    WAYLAND_DISPLAY="$wd"
    return 0
}

CURRENT_USER=$(/usr/bin/id -un)
if ! try_user_runtime "$CURRENT_USER"; then
    if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
        try_user_runtime "$SUDO_USER" || true
    fi
fi

if [ -z "$GUI_USER" ] && have /usr/bin/loginctl; then
    while read -r sid _uid user _rest; do
        [ -n "$sid" ] || continue

        type=$(/usr/bin/loginctl show-session "$sid" -p Type --value 2>/dev/null || true)
        active=$(/usr/bin/loginctl show-session "$sid" -p Active --value 2>/dev/null || true)
        remote=$(/usr/bin/loginctl show-session "$sid" -p Remote --value 2>/dev/null || true)

        if [ "$type" = "wayland" ] && [ "$active" = "yes" ] && [ "$remote" != "yes" ]; then
            if try_user_runtime "$user"; then
                GUI_SESSION="$sid"
                GUI_VT=$(/usr/bin/loginctl show-session "$sid" -p VTNr --value 2>/dev/null || true)
                break
            fi
        fi
    done < <(/usr/bin/loginctl list-sessions --no-legend 2>/dev/null)
fi

if [ -z "$GUI_USER" ]; then
    log "ERROR: Could not find an active local Wayland session."
    exit 1
fi

if [ -z "$GUI_SESSION" ] && have /usr/bin/loginctl; then
    while read -r sid _uid user _rest; do
        [ "$user" = "$GUI_USER" ] || continue
        type=$(/usr/bin/loginctl show-session "$sid" -p Type --value 2>/dev/null || true)
        if [ "$type" = "wayland" ]; then
            GUI_SESSION="$sid"
            GUI_VT=$(/usr/bin/loginctl show-session "$sid" -p VTNr --value 2>/dev/null || true)
            break
        fi
    done < <(/usr/bin/loginctl list-sessions --no-legend 2>/dev/null)
fi

run_gui() {
    if [ "$(/usr/bin/id -u)" = "$GUI_UID" ]; then
        /usr/bin/env \
            HOME="$GUI_HOME" \
            USER="$GUI_USER" \
            LOGNAME="$GUI_USER" \
            XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
            WAYLAND_DISPLAY="$WAYLAND_DISPLAY" \
            PATH="$PATH" \
            "$@"
    elif [ "$(/usr/bin/id -u)" = "0" ]; then
        /usr/sbin/runuser -u "$GUI_USER" -- \
            /usr/bin/env \
            HOME="$GUI_HOME" \
            USER="$GUI_USER" \
            LOGNAME="$GUI_USER" \
            XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
            WAYLAND_DISPLAY="$WAYLAND_DISPLAY" \
            PATH="$PATH" \
            "$@"
    else
        /usr/bin/sudo -n -u "$GUI_USER" \
            /usr/bin/env \
            HOME="$GUI_HOME" \
            USER="$GUI_USER" \
            LOGNAME="$GUI_USER" \
            XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
            WAYLAND_DISPLAY="$WAYLAND_DISPLAY" \
            PATH="$PATH" \
            "$@"
    fi
}

run_gui_background() {
    run_gui /bin/sh -c 'nohup "$@" >/tmp/fieldstation42-kanshi.log 2>&1 </dev/null &' sh "$@"
}

if ! have /usr/bin/wlopm; then
    log "ERROR: /usr/bin/wlopm is missing."
    exit 1
fi

# -----------------------------------------------------------------------------
# Audio
# -----------------------------------------------------------------------------
mpv_command() {
    [ -x /usr/bin/socat ] || return 0
    [ -S /tmp/mpvsocket ] || return 0
    printf '%s\n' "$1" | /usr/bin/socat - /tmp/mpvsocket >/dev/null 2>&1 || true
}

mute_audio() {
    mpv_command '{"command":["set_property","mute",true]}'
    if have /usr/bin/amixer; then
        /usr/bin/amixer set Master mute >/dev/null 2>&1 || true
    fi
}

unmute_audio() {
    mpv_command '{"command":["set_property","mute",false]}'
    if have /usr/bin/amixer; then
        /usr/bin/amixer set Master unmute >/dev/null 2>&1 || true
    fi
}

# -----------------------------------------------------------------------------
# KMS state
# -----------------------------------------------------------------------------
composite_has_crtc() {
    have /usr/bin/kmsprint || return 0

    /usr/bin/kmsprint 2>/dev/null | /usr/bin/awk -v out="$OUTPUT" '
        /^Connector / {
            if (inside) exit
            inside = (index($0, out) > 0)
            next
        }
        inside && /Crtc/ { found=1 }
        END { exit(found ? 0 : 1) }
    '
}

kanshi_is_running() {
    have /usr/bin/pgrep || return 1
    /usr/bin/pgrep -u "$GUI_UID" -x kanshi >/dev/null 2>&1
}

start_kanshi_background() {
    have /usr/bin/kanshi || return 0
    kanshi_is_running && return 0
    log "Restarting kanshi in background."
    run_gui_background /usr/bin/kanshi
}

# -----------------------------------------------------------------------------
# FieldStation42 OSD
# -----------------------------------------------------------------------------
osd_is_running() {
    have /usr/bin/pgrep || return 1
    /usr/bin/pgrep -u "$GUI_UID" -f 'fs42/osd/main.py' >/dev/null 2>&1
}

stop_osd() {
    log "Stopping FieldStation42 OSD."
    run_gui /usr/bin/pkill -f 'fs42/osd/main.py' >/dev/null 2>&1 || true
}

start_osd_background() {
    osd_script="$GUI_HOME/FieldStation42/scripts/OSD.sh"
    fs_root="$GUI_HOME/FieldStation42"

    if [ ! -f "$osd_script" ]; then
        log "WARNING: OSD start script not found: $osd_script"
        return 0
    fi

    if osd_is_running; then
        log "FieldStation42 OSD is already running."
        return 0
    fi

    log "Starting FieldStation42 OSD in background."
    run_gui /bin/sh -c 'cd "$1" && nohup /bin/bash "$2" >/tmp/fieldstation42-osd.log 2>&1 </dev/null &' sh "$fs_root" "$osd_script"
}

# -----------------------------------------------------------------------------
# Fast VT recovery
# -----------------------------------------------------------------------------
chvt_cmd() {
    target="$1"

    if [ "$(/usr/bin/id -u)" = "0" ]; then
        /usr/bin/chvt "$target"
        return $?
    fi

    if have /usr/bin/sudo && /usr/bin/sudo -n true >/dev/null 2>&1; then
        /usr/bin/sudo -n /usr/bin/chvt "$target"
        return $?
    fi

    return 1
}

fast_vt_recovery() {
    [ -n "$GUI_VT" ] || return 1
    [ "$GUI_VT" -gt 0 ] 2>/dev/null || return 1
    have /usr/bin/chvt || return 1

    # If GUI is already VT1, use VT2 as the temporary console.
    TEMP_VT=1
    if [ "$GUI_VT" = "1" ]; then
        TEMP_VT=2
    fi

    log "Fast KMS reset: VT${TEMP_VT} -> VT${GUI_VT}."

    chvt_cmd "$TEMP_VT" || return 1
    /usr/bin/sleep 0.20
    chvt_cmd "$GUI_VT" || return 1
    /usr/bin/sleep 0.20

    return 0
}

# -----------------------------------------------------------------------------
# Read persisted OFF state
# -----------------------------------------------------------------------------
STATE="on"
KANSHI_WAS_RUNNING=0

if [ -f "$STATE_FILE" ]; then
    if /usr/bin/grep -qx 'state=off' "$STATE_FILE" 2>/dev/null; then
        STATE="off"
    fi
    if /usr/bin/grep -qx 'kanshi=1' "$STATE_FILE" 2>/dev/null; then
        KANSHI_WAS_RUNNING=1
    fi
fi

# -----------------------------------------------------------------------------
# Toggle ON
# -----------------------------------------------------------------------------
if [ "$STATE" = "off" ]; then
    log "Restoring $OUTPUT..."

    # Ask Wayland to wake it once. Do not wait seconds for retries.
    run_gui /usr/bin/wlopm --on "$OUTPUT" >/dev/null 2>&1 || true
    /usr/bin/sleep 0.10

    # The known failure mode is: Wayland says enabled but KMS has no CRTC.
    # Go directly to the VT reset that has proven to restore the scanout.
    if ! composite_has_crtc; then
        fast_vt_recovery || true
    fi

    # One immediate wake request after returning to the GUI VT.
    run_gui /usr/bin/wlopm --on "$OUTPUT" >/dev/null 2>&1 || true
    /usr/bin/sleep 0.10

    if composite_has_crtc; then
        # Restore sound as soon as real scanout exists.
        unmute_audio
        /bin/rm -f "$STATE_FILE"
        log "$OUTPUT restored; audio unmuted."

        # Restart the FieldStation42 OSD without delaying the screen restore.
        start_osd_background

        # Only restart kanshi if it was actually running before OFF.
        # Do it after video/audio are restored so it cannot delay the button.
        if [ "$KANSHI_WAS_RUNNING" -eq 1 ]; then
            start_kanshi_background
        fi

        exit 0
    fi

    # One slightly longer fallback VT bounce, still much faster than the old
    # multi-second retry chain.
    log "$OUTPUT still has no CRTC; retrying KMS reset once."

    if [ -n "$GUI_VT" ] && [ "$GUI_VT" -gt 0 ] 2>/dev/null; then
        TEMP_VT=1
        [ "$GUI_VT" = "1" ] && TEMP_VT=2

        chvt_cmd "$TEMP_VT" || true
        /usr/bin/sleep 0.50
        chvt_cmd "$GUI_VT" || true
        /usr/bin/sleep 0.30
    fi

    run_gui /usr/bin/wlopm --on "$OUTPUT" >/dev/null 2>&1 || true
    /usr/bin/sleep 0.10

    if composite_has_crtc; then
        unmute_audio
        /bin/rm -f "$STATE_FILE"
        log "$OUTPUT restored; audio unmuted."

        start_osd_background

        if [ "$KANSHI_WAS_RUNNING" -eq 1 ]; then
            start_kanshi_background
        fi

        exit 0
    fi

    log "ERROR: $OUTPUT still has no KMS CRTC. Audio remains muted."
    exit 1
fi

# -----------------------------------------------------------------------------
# Toggle OFF
# -----------------------------------------------------------------------------
log "Turning $OUTPUT off..."

mute_audio
stop_osd

KANSHI_WAS_RUNNING=0
if kanshi_is_running; then
    KANSHI_WAS_RUNNING=1
    log "Stopping kanshi while composite is off."
    run_gui /usr/bin/pkill -x kanshi >/dev/null 2>&1 || true
    # No fixed half-second wait here.
fi

if ! run_gui /usr/bin/wlopm --off "$OUTPUT"; then
    log "ERROR: wlopm could not turn $OUTPUT off."
    unmute_audio
    start_osd_background

    if [ "$KANSHI_WAS_RUNNING" -eq 1 ]; then
        start_kanshi_background
    fi

    exit 1
fi

{
    echo 'state=off'
    echo "kanshi=$KANSHI_WAS_RUNNING"
} > "$STATE_FILE"
/bin/chmod 666 "$STATE_FILE" 2>/dev/null || true

log "$OUTPUT powered off; audio muted."
exit 0
